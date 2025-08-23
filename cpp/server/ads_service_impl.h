#pragma once

#include <grpcpp/grpcpp.h>
#include "ads.grpc.pb.h"
#include "ad_generator.h"

using grpc::ServerContext;
using grpc::ServerReaderWriter;
using grpc::Status;
using ads::Context;
using ads::AdsList;
using ads::AdsService;

class AdsServiceImpl final : public AdsService::Service {
public:
    Status GetAds(ServerContext* context,
                  ServerReaderWriter<AdsList, Context>* stream) override;

private:
    AdGenerator ad_generator_;
};