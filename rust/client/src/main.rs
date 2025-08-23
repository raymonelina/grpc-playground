use std::collections::HashMap;
use std::time::{Duration, Instant};
use tokio::time::{sleep, timeout};
use tokio_stream::wrappers::ReceiverStream;
use tonic::{transport::Channel, Request, Status};
use rand::Rng;
use tracing::{info, warn, error, debug, span, Level};

// Include the generated protobuf code
pub mod ads {
    tonic::include_proto!("ads");
}

use ads::{ads_service_client::AdsServiceClient, Context, AdsList};

pub struct AdsClient {
    client: AdsServiceClient<Channel>,
}

impl AdsClient {
    /// Create a new AdsClient and connect to the server
    pub async fn new(server_addr: &str) -> Result<Self, Box<dyn std::error::Error>> {
        info!("Connecting to server at {}", server_addr);
        let client = AdsServiceClient::connect(server_addr.to_string()).await?;
        Ok(AdsClient { client })
    }

    /// Get ads using bidirectional streaming with the specified context
    pub async fn get_ads(
        &mut self,
        query: String,
        asin_id: String,
        understanding: String,
    ) -> Result<Option<AdsList>, Box<dyn std::error::Error>> {
        let overall_start = Instant::now();
        let span = span!(Level::INFO, "bidirectional_stream", 
                        query = %query, 
                        asin_id = %asin_id, 
                        understanding_provided = !understanding.is_empty());
        let _enter = span.enter();
        
        info!(
            query = %query,
            asin_id = %asin_id,
            understanding_provided = !understanding.is_empty(),
            "Starting bidirectional stream"
        );
        
        // Create a channel for sending Context messages
        let (tx, rx) = tokio::sync::mpsc::channel(10);
        let request_stream = ReceiverStream::new(rx);
        
        // Start the bidirectional stream
        let mut response_stream = self.client
            .get_ads(Request::new(request_stream))
            .await?
            .into_inner();
        
        // Buffer for AdsList messages by version
        let mut ads_buffer: HashMap<u32, AdsList> = HashMap::new();
        
        // Send first Context message
        let first_context = Context {
            query: query.clone(),
            asin_id: asin_id.clone(),
            understanding: "".to_string(), // Empty initially
        };
        
        info!(
            context_number = 1,
            understanding_empty = true,
            elapsed_ms = overall_start.elapsed().as_millis() as u64,
            "Sending Context message"
        );
        tx.send(first_context).await.map_err(|e| format!("Failed to send first context: {}", e))?;
        
        // Wait 50ms before sending second Context
        debug!("Waiting 50ms before second Context message");
        sleep(Duration::from_millis(50)).await;
        
        // Send second Context message with understanding
        let second_context = Context {
            query: query.clone(),
            asin_id: asin_id.clone(),
            understanding: understanding.clone(),
        };
        
        info!(
            context_number = 2,
            understanding_length = understanding.len(),
            elapsed_ms = overall_start.elapsed().as_millis() as u64,
            "Sending Context message"
        );
        tx.send(second_context).await.map_err(|e| format!("Failed to send second context: {}", e))?;
        
        // Close the sending side (half-close)
        drop(tx);
        info!(
            elapsed_ms = overall_start.elapsed().as_millis() as u64,
            "Half-closed client stream"
        );
        
        // Generate random timeout between 30-120ms with jitter
        let mut rng = rand::thread_rng();
        let base_timeout = rng.gen_range(30..=120);
        let jitter = rng.gen_range(-5..=5);
        let timeout_ms = (base_timeout + jitter).max(30).min(120);
        let timeout_duration = Duration::from_millis(timeout_ms as u64);
        
        info!(
            timeout_ms = timeout_ms,
            min_timeout = 30,
            max_timeout = 120,
            "Generated random timeout for result selection"
        );
        
        // Start receiving responses and apply timeout
        let receive_task = async {
            while let Some(response) = response_stream.message().await? {
                let version = response.version;
                let ads_count = response.ads.len();
                let elapsed_ms = overall_start.elapsed().as_millis() as u64;
                let is_replacement = ads_buffer.contains_key(&version);
                
                info!(
                    version = version,
                    ads_count = ads_count,
                    elapsed_ms = elapsed_ms,
                    is_replacement = is_replacement,
                    "Received AdsList"
                );
                
                // Log debug details about the ads if debug level is enabled
                for (i, ad) in response.ads.iter().enumerate() {
                    debug!(
                        version = version,
                        ad_index = i,
                        asin_id = %ad.asin_id,
                        ad_id = %ad.ad_id,
                        score = format!("{:.3}", ad.score),
                        "Ad details"
                    );
                }
                
                // Buffer the response, replacing older versions if they exist
                if let Some(old_ads) = ads_buffer.insert(version, response) {
                    debug!(
                        version = version,
                        old_ads_count = old_ads.ads.len(),
                        new_ads_count = ads_count,
                        "Replaced AdsList in buffer"
                    );
                } else {
                    debug!(
                        version = version,
                        ads_count = ads_count,
                        "Added new AdsList to buffer"
                    );
                }
            }
            Ok::<(), Status>(())
        };
        
        // Apply timeout to the receiving process
        match timeout(timeout_duration, receive_task).await {
            Ok(Ok(())) => {
                info!(
                    elapsed_ms = overall_start.elapsed().as_millis() as u64,
                    versions_received = ads_buffer.len(),
                    "Stream completed normally before timeout"
                );
            }
            Ok(Err(e)) => {
                warn!(
                    error = %e,
                    elapsed_ms = overall_start.elapsed().as_millis() as u64,
                    "Stream error occurred"
                );
            }
            Err(_) => {
                info!(
                    timeout_ms = timeout_ms,
                    elapsed_ms = overall_start.elapsed().as_millis() as u64,
                    versions_received = ads_buffer.len(),
                    "Client timeout reached - proceeding with available results"
                );
            }
        }
        
        // Log buffer state for debugging
        let mut versions: Vec<u32> = ads_buffer.keys().cloned().collect();
        versions.sort();
        debug!(
            buffer_size = ads_buffer.len(),
            available_versions = ?versions,
            elapsed_ms = overall_start.elapsed().as_millis() as u64,
            "Buffer state at timeout"
        );
        
        // Return the most recent AdsList (highest version number)
        if let Some(latest_ads) = ads_buffer.values().max_by_key(|ads| ads.version) {
            let total_duration_ms = overall_start.elapsed().as_millis() as u64;
            
            info!(
                selected_version = latest_ads.version,
                ads_count = latest_ads.ads.len(),
                total_duration_ms = total_duration_ms,
                versions_considered = ads_buffer.len(),
                "FINAL RESULT: Selected AdsList"
            );
            
            // Log performance summary
            info!(
                operation = "bidirectional_stream",
                total_duration_ms = total_duration_ms,
                timeout_used_ms = timeout_ms,
                versions_received = ads_buffer.len(),
                final_version = latest_ads.version,
                "Performance summary"
            );
            
            Ok(Some(latest_ads.clone()))
        } else {
            let total_duration_ms = overall_start.elapsed().as_millis() as u64;
            warn!(
                total_duration_ms = total_duration_ms,
                timeout_ms = timeout_ms,
                buffer_size = ads_buffer.len(),
                "FINAL RESULT: No AdsList received within timeout"
            );
            Ok(None)
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Parse command line arguments or use defaults
    let server_addr = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "http://127.0.0.1:50051".to_string());
    
    let query = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "coffee maker".to_string());
    
    let asin_id = std::env::args()
        .nth(3)
        .unwrap_or_else(|| "B000123".to_string());

    info!("Starting Rust ADS client");
    info!("Server address: {}", server_addr);
    info!("Query: {}", query);
    info!("ASIN ID: {}", asin_id);

    // Create client and connect
    let mut client = AdsClient::new(&server_addr).await?;

    // Get ads using bidirectional streaming
    let understanding = "refined understanding based on query analysis".to_string();
    match client.get_ads(query, asin_id, understanding).await {
        Ok(Some(ads_list)) => {
            info!("SUCCESS: Final result is AdsList version {} containing {} ads", 
                  ads_list.version, ads_list.ads.len());
            for (i, ad) in ads_list.ads.iter().enumerate() {
                info!("  Ad {}: asin_id={}, ad_id={}, score={:.3}", 
                      i + 1, ad.asin_id, ad.ad_id, ad.score);
            }
        }
        Ok(None) => {
            warn!("FAILURE: No AdsList received within timeout - no final result available");
        }
        Err(e) => {
            error!("ERROR: Failed to get ads: {}", e);
            return Err(e);
        }
    }

    info!("Client completed successfully");
    Ok(())
}
