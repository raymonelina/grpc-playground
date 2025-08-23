#include "ad_generator.h"
#include <functional>
#include <random>
#include <sstream>
#include <iomanip>

AdsList AdGenerator::generateAds(const Context& context, int version) {
    AdsList ads_list;
    ads_list.set_version(version);
    
    // Generate 5-10 ads based on context
    std::hash<std::string> hasher;
    size_t seed = hasher(context.query() + context.asin_id() + std::to_string(version));
    std::mt19937 gen(seed);
    std::uniform_int_distribution<> ad_count_dist(5, 10);
    
    int num_ads = ad_count_dist(gen);
    
    for (int i = 0; i < num_ads; i++) {
        ads::Ad* ad = ads_list.add_ads();
        
        // Generate asin_id based on context and index
        std::stringstream asin_stream;
        asin_stream << "B" << std::setfill('0') << std::setw(6) 
                   << (hasher(context.asin_id() + std::to_string(i)) % 1000000);
        ad->set_asin_id(asin_stream.str());
        
        // Generate ad_id
        ad->set_ad_id(generateAdId(ad->asin_id(), i));
        
        // Calculate score based on context and version
        double score = calculateScore(context.query(), context.asin_id(), 
                                    context.understanding(), version);
        
        // Add some variation per ad
        std::uniform_real_distribution<> score_variation(-0.1, 0.1);
        score += score_variation(gen);
        
        // Clamp score to [0.0, 1.0]
        score = std::max(0.0, std::min(1.0, score));
        ad->set_score(score);
    }
    
    return ads_list;
}

double AdGenerator::calculateScore(const std::string& query, const std::string& asin_id, 
                                 const std::string& understanding, int version) {
    std::hash<std::string> hasher;
    
    // Base score from query and asin_id
    double base_score = static_cast<double>(hasher(query + asin_id) % 1000) / 1000.0;
    
    // Understanding boost (when understanding is provided)
    double understanding_boost = 0.0;
    if (!understanding.empty()) {
        understanding_boost = static_cast<double>(hasher(understanding) % 200) / 1000.0; // 0-0.2 boost
    }
    
    // Version refinement (progressive improvement)
    double version_multiplier = 0.7 + (version * 0.1); // 0.8, 0.9, 1.0 for versions 1, 2, 3
    
    double final_score = (base_score + understanding_boost) * version_multiplier;
    
    // Ensure score is in valid range
    return std::max(0.0, std::min(1.0, final_score));
}

std::string AdGenerator::generateAdId(const std::string& asin_id, int index) {
    std::hash<std::string> hasher;
    size_t hash_value = hasher(asin_id + std::to_string(index));
    
    std::stringstream ad_id_stream;
    ad_id_stream << "AD" << std::setfill('0') << std::setw(8) << (hash_value % 100000000);
    
    return ad_id_stream.str();
}