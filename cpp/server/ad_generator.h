#pragma once

#include "ads.pb.h"
#include <string>

using ads::Context;
using ads::AdsList;

class AdGenerator {
public:
    AdsList generateAds(const Context& context, int version);

private:
    double calculateScore(const std::string& query, const std::string& asin_id, 
                         const std::string& understanding, int version);
    std::string generateAdId(const std::string& asin_id, int index);
};