package com.example.ads.server;

import ads.Ads;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * Mock ad generation algorithm that creates realistic ads based on Context information.
 * Implements progressive refinement logic across versions 1, 2, and 3.
 */
public class AdGenerator {
    private static final Random random = new Random();
    
    // Mock product categories for realistic ad generation
    private static final String[] PRODUCT_CATEGORIES = {
        "Electronics", "Home & Kitchen", "Books", "Clothing", "Sports", 
        "Beauty", "Automotive", "Tools", "Toys", "Health"
    };
    
    /**
     * Generate a list of mock ads based on the provided context and version.
     * 
     * @param context The search context containing query, asin_id, and understanding
     * @param version The version number (1, 2, or 3) for progressive refinement
     * @return AdsList containing 5-10 mock ads with realistic data
     */
    public Ads.AdsList generateAds(Ads.Context context, int version) {
        List<Ads.Ad> ads = new ArrayList<>();
        
        // Generate 5-10 ads based on context
        int adCount = 5 + random.nextInt(6); // 5-10 ads
        
        for (int i = 0; i < adCount; i++) {
            Ads.Ad ad = generateSingleAd(context, version, i);
            ads.add(ad);
        }
        
        return Ads.AdsList.newBuilder()
                .addAllAds(ads)
                .setVersion(version)
                .build();
    }
    
    /**
     * Generate a single ad with progressive refinement based on version.
     */
    private Ads.Ad generateSingleAd(Ads.Context context, int version, int index) {
        // Base scoring using hash of query + asin_id for deterministic results
        double baseScore = generateBaseScore(context.getQuery(), context.getAsinId(), index);
        
        // Apply version-based refinement
        double refinedScore = applyVersionRefinement(baseScore, context, version);
        
        // Apply understanding boost for versions 2 and 3
        if (version >= 2 && !context.getUnderstanding().isEmpty()) {
            refinedScore = applyUnderstandingBoost(refinedScore, context.getUnderstanding());
        }
        
        // Generate realistic asin_id and ad_id
        String adAsinId = generateAdAsinId(context, index);
        String adId = generateAdId(context, version, index);
        
        return Ads.Ad.newBuilder()
                .setAsinId(adAsinId)
                .setAdId(adId)
                .setScore(Math.min(1.0, Math.max(0.0, refinedScore))) // Clamp to [0.0, 1.0]
                .build();
    }
    
    /**
     * Generate base score using deterministic hash of context information.
     */
    private double generateBaseScore(String query, String asinId, int index) {
        // Create a deterministic hash for consistent results
        int hash = (query + asinId + index).hashCode();
        
        // Convert hash to a score between 0.3 and 0.8 (reasonable base range)
        return 0.3 + (Math.abs(hash) % 1000) / 2000.0;
    }
    
    /**
     * Apply version-based refinement to improve scores progressively.
     */
    private double applyVersionRefinement(double baseScore, Ads.Context context, int version) {
        switch (version) {
            case 1:
                // Version 1: Basic scoring with some randomness
                return baseScore + (random.nextGaussian() * 0.05);
                
            case 2:
                // Version 2: Improved scoring with context consideration
                double improvement = calculateContextRelevance(context) * 0.1;
                return baseScore + improvement + (random.nextGaussian() * 0.03);
                
            case 3:
                // Version 3: Best scoring with full context and understanding
                double maxImprovement = calculateContextRelevance(context) * 0.15;
                if (!context.getUnderstanding().isEmpty()) {
                    maxImprovement += 0.05; // Additional boost for understanding
                }
                return baseScore + maxImprovement + (random.nextGaussian() * 0.02);
                
            default:
                return baseScore;
        }
    }
    
    /**
     * Calculate relevance score based on context information.
     */
    private double calculateContextRelevance(Ads.Context context) {
        double relevance = 0.0;
        
        // Query relevance (longer queries generally indicate more specific intent)
        if (!context.getQuery().isEmpty()) {
            relevance += Math.min(0.3, context.getQuery().length() / 50.0);
        }
        
        // ASIN relevance (having a specific product context is valuable)
        if (!context.getAsinId().isEmpty()) {
            relevance += 0.2;
        }
        
        return relevance;
    }
    
    /**
     * Apply understanding boost for refined queries.
     */
    private double applyUnderstandingBoost(double score, String understanding) {
        // Understanding provides additional context for better targeting
        double boost = Math.min(0.1, understanding.length() / 100.0);
        return score + boost;
    }
    
    /**
     * Generate realistic ASIN ID for the ad.
     */
    private String generateAdAsinId(Ads.Context context, int index) {
        // Use context ASIN as base, or generate related ASINs
        if (!context.getAsinId().isEmpty() && random.nextDouble() < 0.3) {
            // 30% chance to use the same ASIN (exact match)
            return context.getAsinId();
        } else {
            // Generate related ASIN
            String category = PRODUCT_CATEGORIES[Math.abs((context.getQuery() + index).hashCode()) % PRODUCT_CATEGORIES.length];
            return "B" + String.format("%06d", Math.abs((category + index).hashCode()) % 1000000);
        }
    }
    
    /**
     * Generate unique ad ID.
     */
    private String generateAdId(Ads.Context context, int version, int index) {
        // Generate unique ad ID based on context, version, and index
        int hash = (context.getQuery() + context.getAsinId() + version + index).hashCode();
        return "AD" + String.format("%08d", Math.abs(hash) % 100000000);
    }
}