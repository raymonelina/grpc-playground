use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};
use tokio::time::sleep;
use tokio_stream::{wrappers::ReceiverStream, Stream, StreamExt};
use tonic::{transport::Server, Request, Response, Status, Streaming};
use tracing::{info, warn, debug, error, span, Level};

// Include the generated protobuf code
pub mod ads {
    tonic::include_proto!("ads");
}

use ads::{ads_service_server::{AdsService, AdsServiceServer}, Ad, AdsList, Context};

#[derive(Debug, Default)]
pub struct AdsServiceImpl {
    session_counter: AtomicU64,
}

#[tonic::async_trait]
impl AdsService for AdsServiceImpl {
    type GetAdsStream = Pin<Box<dyn Stream<Item = Result<AdsList, Status>> + Send>>;

    async fn get_ads(
        &self,
        request: Request<Streaming<Context>>,
    ) -> Result<Response<Self::GetAdsStream>, Status> {
        let session_id = self.session_counter.fetch_add(1, Ordering::SeqCst) + 1;
        let session_start = Instant::now();
        
        let span = span!(Level::INFO, "session", session_id = session_id);
        let _enter = span.enter();
        
        info!(
            session_id = session_id,
            thread = ?std::thread::current().id(),
            "New bidirectional stream opened"
        );
        
        let mut in_stream = request.into_inner();
        let (tx, rx) = tokio::sync::mpsc::channel(128);
        
        tokio::spawn(async move {
            let mut context_count = 0;
            let mut last_context: Option<Context> = None;
            
            while let Some(context_result) = in_stream.next().await {
                match context_result {
                    Ok(context) => {
                        context_count += 1;
                        let context_processing_start = Instant::now();
                        
                        info!(
                            session_id = session_id,
                            context_number = context_count,
                            query = %context.query,
                            asin_id = %context.asin_id,
                            understanding_length = context.understanding.len(),
                            understanding_empty = context.understanding.is_empty(),
                            session_elapsed_ms = session_start.elapsed().as_millis() as u64,
                            "Received Context message"
                        );
                        
                        // Generate and send AdsList based on context count
                        let ad_gen_start = Instant::now();
                        let ads_list = generate_ads(&context, context_count);
                        let generation_ms = ad_gen_start.elapsed().as_millis() as u64;
                        let context_processing_ms = context_processing_start.elapsed().as_millis() as u64;
                        
                        info!(
                            session_id = session_id,
                            version = context_count,
                            ads_count = ads_list.ads.len(),
                            generation_ms = generation_ms,
                            context_processing_ms = context_processing_ms,
                            "Sending AdsList"
                        );
                        
                        // Log debug details about the ads if debug level is enabled
                        for (i, ad) in ads_list.ads.iter().enumerate() {
                            debug!(
                                session_id = session_id,
                                version = context_count,
                                ad_index = i,
                                asin_id = %ad.asin_id,
                                ad_id = %ad.ad_id,
                                score = format!("{:.3}", ad.score),
                                "Generated ad details"
                            );
                        }
                        
                        if let Err(_) = tx.send(Ok(ads_list)).await {
                            warn!(
                                session_id = session_id,
                                context_number = context_count,
                                "Failed to send AdsList - receiver dropped"
                            );
                            break;
                        }
                        
                        last_context = Some(context);
                        
                        // If this is the second context, schedule the delayed third response
                        if context_count == 2 {
                            info!(
                                session_id = session_id,
                                delay_ms = 50,
                                "Scheduling delayed version 3 AdsList"
                            );
                            
                            let tx_clone = tx.clone();
                            let context_clone = last_context.clone().unwrap();
                            let session_start_clone = session_start;
                            tokio::spawn(async move {
                                sleep(Duration::from_millis(50)).await;
                                
                                let final_ad_gen_start = Instant::now();
                                let ads_list = generate_ads(&context_clone, 3);
                                let generation_ms = final_ad_gen_start.elapsed().as_millis() as u64;
                                
                                info!(
                                    session_id = session_id,
                                    version = 3,
                                    ads_count = ads_list.ads.len(),
                                    generation_ms = generation_ms,
                                    session_elapsed_ms = session_start_clone.elapsed().as_millis() as u64,
                                    "Sending delayed AdsList"
                                );
                                
                                // Log debug details about the ads if debug level is enabled
                                for (i, ad) in ads_list.ads.iter().enumerate() {
                                    debug!(
                                        session_id = session_id,
                                        version = 3,
                                        ad_index = i,
                                        asin_id = %ad.asin_id,
                                        ad_id = %ad.ad_id,
                                        score = format!("{:.3}", ad.score),
                                        "Generated ad details"
                                    );
                                }
                                
                                if let Err(_) = tx_clone.send(Ok(ads_list)).await {
                                    warn!(
                                        session_id = session_id,
                                        "Failed to send delayed AdsList - receiver dropped"
                                    );
                                } else {
                                    info!(
                                        session_id = session_id,
                                        total_contexts = context_count,
                                        total_duration_ms = session_start_clone.elapsed().as_millis() as u64,
                                        "Stream completed successfully"
                                    );
                                }
                                // Close the channel after sending the third response
                                drop(tx_clone);
                            });
                        }
                    }
                    Err(e) => {
                        error!(
                            session_id = session_id,
                            contexts_processed = context_count,
                            error = %e,
                            session_elapsed_ms = session_start.elapsed().as_millis() as u64,
                            "Error in bidirectional stream"
                        );
                        let _ = tx.send(Err(e)).await;
                        break;
                    }
                }
            }
            
            info!(
                session_id = session_id,
                contexts_received = context_count,
                session_elapsed_ms = session_start.elapsed().as_millis() as u64,
                "Client half-closed stream"
            );
        });
        
        let out_stream = ReceiverStream::new(rx);
        Ok(Response::new(Box::pin(out_stream) as Self::GetAdsStream))
    }
}

// Mock ad generation with Context-based scoring and progressive refinement
fn generate_ads(context: &Context, version: u32) -> AdsList {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use rand::{Rng, SeedableRng};
    use rand::rngs::StdRng;
    
    // Create a deterministic seed based on context for reproducible results
    let mut hasher = DefaultHasher::new();
    context.query.hash(&mut hasher);
    context.asin_id.hash(&mut hasher);
    let seed = hasher.finish();
    let mut rng = StdRng::seed_from_u64(seed);
    
    // Generate 5-10 mock ads as per requirement 2.5
    let num_ads = rng.gen_range(5..=10);
    let mut ads = Vec::with_capacity(num_ads);
    
    for i in 0..num_ads {
        // Base score calculation using hash of query + asin_id
        let mut ad_hasher = DefaultHasher::new();
        context.query.hash(&mut ad_hasher);
        context.asin_id.hash(&mut ad_hasher);
        i.hash(&mut ad_hasher); // Add index for variation
        let base_hash = ad_hasher.finish();
        let mut base_score = (base_hash % 1000) as f64 / 1000.0; // 0.0 to 1.0
        
        // Understanding boost - additional scoring when understanding is provided (requirement 2.6)
        if !context.understanding.is_empty() {
            let mut understanding_hasher = DefaultHasher::new();
            context.understanding.hash(&mut understanding_hasher);
            let understanding_boost = (understanding_hasher.finish() % 200) as f64 / 1000.0; // 0.0 to 0.2 boost
            base_score += understanding_boost;
        }
        
        // Version refinement - progressive improvement across versions
        let version_multiplier = match version {
            1 => 0.7, // Initial results are less refined
            2 => 0.9, // Better results with complete context
            3 => 1.1, // Best results after processing delay
            _ => 1.0,
        };
        base_score *= version_multiplier;
        
        // Add controlled randomness for realistic variation
        let randomness = rng.gen_range(-0.1..=0.1);
        base_score += randomness;
        
        // Clamp score to valid range [0.0, 1.0]
        base_score = base_score.max(0.0).min(1.0);
        
        // Generate realistic ad_id
        let ad_id = format!("ad_{}_{}_v{}", context.asin_id, i + 1, version);
        
        ads.push(Ad {
            asin_id: context.asin_id.clone(),
            ad_id,
            score: base_score,
        });
    }
    
    // Sort ads by score in descending order for better user experience
    ads.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    
    AdsList {
        ads,
        version,
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();
    
    let addr = "127.0.0.1:50051".parse()?;
    let ads_service = AdsServiceImpl::default();
    
    info!("Starting Rust Ads server on {}", addr);
    
    Server::builder()
        .add_service(AdsServiceServer::new(ads_service))
        .serve(addr)
        .await?;
    
    Ok(())
}
