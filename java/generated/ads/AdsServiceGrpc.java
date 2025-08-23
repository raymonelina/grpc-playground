package ads;

import static io.grpc.MethodDescriptor.generateFullMethodName;

/**
 * <pre>
 * Service definition for bidirectional streaming ad serving
 * </pre>
 */
@javax.annotation.Generated(
    value = "by gRPC proto compiler (version 1.66.0)",
    comments = "Source: ads.proto")
@io.grpc.stub.annotations.GrpcGenerated
public final class AdsServiceGrpc {

  private AdsServiceGrpc() {}

  public static final java.lang.String SERVICE_NAME = "ads.AdsService";

  // Static method descriptors that strictly reflect the proto.
  private static volatile io.grpc.MethodDescriptor<ads.Ads.Context,
      ads.Ads.AdsList> getGetAdsMethod;

  @io.grpc.stub.annotations.RpcMethod(
      fullMethodName = SERVICE_NAME + '/' + "GetAds",
      requestType = ads.Ads.Context.class,
      responseType = ads.Ads.AdsList.class,
      methodType = io.grpc.MethodDescriptor.MethodType.BIDI_STREAMING)
  public static io.grpc.MethodDescriptor<ads.Ads.Context,
      ads.Ads.AdsList> getGetAdsMethod() {
    io.grpc.MethodDescriptor<ads.Ads.Context, ads.Ads.AdsList> getGetAdsMethod;
    if ((getGetAdsMethod = AdsServiceGrpc.getGetAdsMethod) == null) {
      synchronized (AdsServiceGrpc.class) {
        if ((getGetAdsMethod = AdsServiceGrpc.getGetAdsMethod) == null) {
          AdsServiceGrpc.getGetAdsMethod = getGetAdsMethod =
              io.grpc.MethodDescriptor.<ads.Ads.Context, ads.Ads.AdsList>newBuilder()
              .setType(io.grpc.MethodDescriptor.MethodType.BIDI_STREAMING)
              .setFullMethodName(generateFullMethodName(SERVICE_NAME, "GetAds"))
              .setSampledToLocalTracing(true)
              .setRequestMarshaller(io.grpc.protobuf.ProtoUtils.marshaller(
                  ads.Ads.Context.getDefaultInstance()))
              .setResponseMarshaller(io.grpc.protobuf.ProtoUtils.marshaller(
                  ads.Ads.AdsList.getDefaultInstance()))
              .setSchemaDescriptor(new AdsServiceMethodDescriptorSupplier("GetAds"))
              .build();
        }
      }
    }
    return getGetAdsMethod;
  }

  /**
   * Creates a new async stub that supports all call types for the service
   */
  public static AdsServiceStub newStub(io.grpc.Channel channel) {
    io.grpc.stub.AbstractStub.StubFactory<AdsServiceStub> factory =
      new io.grpc.stub.AbstractStub.StubFactory<AdsServiceStub>() {
        @java.lang.Override
        public AdsServiceStub newStub(io.grpc.Channel channel, io.grpc.CallOptions callOptions) {
          return new AdsServiceStub(channel, callOptions);
        }
      };
    return AdsServiceStub.newStub(factory, channel);
  }

  /**
   * Creates a new blocking-style stub that supports unary and streaming output calls on the service
   */
  public static AdsServiceBlockingStub newBlockingStub(
      io.grpc.Channel channel) {
    io.grpc.stub.AbstractStub.StubFactory<AdsServiceBlockingStub> factory =
      new io.grpc.stub.AbstractStub.StubFactory<AdsServiceBlockingStub>() {
        @java.lang.Override
        public AdsServiceBlockingStub newStub(io.grpc.Channel channel, io.grpc.CallOptions callOptions) {
          return new AdsServiceBlockingStub(channel, callOptions);
        }
      };
    return AdsServiceBlockingStub.newStub(factory, channel);
  }

  /**
   * Creates a new ListenableFuture-style stub that supports unary calls on the service
   */
  public static AdsServiceFutureStub newFutureStub(
      io.grpc.Channel channel) {
    io.grpc.stub.AbstractStub.StubFactory<AdsServiceFutureStub> factory =
      new io.grpc.stub.AbstractStub.StubFactory<AdsServiceFutureStub>() {
        @java.lang.Override
        public AdsServiceFutureStub newStub(io.grpc.Channel channel, io.grpc.CallOptions callOptions) {
          return new AdsServiceFutureStub(channel, callOptions);
        }
      };
    return AdsServiceFutureStub.newStub(factory, channel);
  }

  /**
   * <pre>
   * Service definition for bidirectional streaming ad serving
   * </pre>
   */
  public interface AsyncService {

    /**
     */
    default io.grpc.stub.StreamObserver<ads.Ads.Context> getAds(
        io.grpc.stub.StreamObserver<ads.Ads.AdsList> responseObserver) {
      return io.grpc.stub.ServerCalls.asyncUnimplementedStreamingCall(getGetAdsMethod(), responseObserver);
    }
  }

  /**
   * Base class for the server implementation of the service AdsService.
   * <pre>
   * Service definition for bidirectional streaming ad serving
   * </pre>
   */
  public static abstract class AdsServiceImplBase
      implements io.grpc.BindableService, AsyncService {

    @java.lang.Override public final io.grpc.ServerServiceDefinition bindService() {
      return AdsServiceGrpc.bindService(this);
    }
  }

  /**
   * A stub to allow clients to do asynchronous rpc calls to service AdsService.
   * <pre>
   * Service definition for bidirectional streaming ad serving
   * </pre>
   */
  public static final class AdsServiceStub
      extends io.grpc.stub.AbstractAsyncStub<AdsServiceStub> {
    private AdsServiceStub(
        io.grpc.Channel channel, io.grpc.CallOptions callOptions) {
      super(channel, callOptions);
    }

    @java.lang.Override
    protected AdsServiceStub build(
        io.grpc.Channel channel, io.grpc.CallOptions callOptions) {
      return new AdsServiceStub(channel, callOptions);
    }

    /**
     */
    public io.grpc.stub.StreamObserver<ads.Ads.Context> getAds(
        io.grpc.stub.StreamObserver<ads.Ads.AdsList> responseObserver) {
      return io.grpc.stub.ClientCalls.asyncBidiStreamingCall(
          getChannel().newCall(getGetAdsMethod(), getCallOptions()), responseObserver);
    }
  }

  /**
   * A stub to allow clients to do synchronous rpc calls to service AdsService.
   * <pre>
   * Service definition for bidirectional streaming ad serving
   * </pre>
   */
  public static final class AdsServiceBlockingStub
      extends io.grpc.stub.AbstractBlockingStub<AdsServiceBlockingStub> {
    private AdsServiceBlockingStub(
        io.grpc.Channel channel, io.grpc.CallOptions callOptions) {
      super(channel, callOptions);
    }

    @java.lang.Override
    protected AdsServiceBlockingStub build(
        io.grpc.Channel channel, io.grpc.CallOptions callOptions) {
      return new AdsServiceBlockingStub(channel, callOptions);
    }
  }

  /**
   * A stub to allow clients to do ListenableFuture-style rpc calls to service AdsService.
   * <pre>
   * Service definition for bidirectional streaming ad serving
   * </pre>
   */
  public static final class AdsServiceFutureStub
      extends io.grpc.stub.AbstractFutureStub<AdsServiceFutureStub> {
    private AdsServiceFutureStub(
        io.grpc.Channel channel, io.grpc.CallOptions callOptions) {
      super(channel, callOptions);
    }

    @java.lang.Override
    protected AdsServiceFutureStub build(
        io.grpc.Channel channel, io.grpc.CallOptions callOptions) {
      return new AdsServiceFutureStub(channel, callOptions);
    }
  }

  private static final int METHODID_GET_ADS = 0;

  private static final class MethodHandlers<Req, Resp> implements
      io.grpc.stub.ServerCalls.UnaryMethod<Req, Resp>,
      io.grpc.stub.ServerCalls.ServerStreamingMethod<Req, Resp>,
      io.grpc.stub.ServerCalls.ClientStreamingMethod<Req, Resp>,
      io.grpc.stub.ServerCalls.BidiStreamingMethod<Req, Resp> {
    private final AsyncService serviceImpl;
    private final int methodId;

    MethodHandlers(AsyncService serviceImpl, int methodId) {
      this.serviceImpl = serviceImpl;
      this.methodId = methodId;
    }

    @java.lang.Override
    @java.lang.SuppressWarnings("unchecked")
    public void invoke(Req request, io.grpc.stub.StreamObserver<Resp> responseObserver) {
      switch (methodId) {
        default:
          throw new AssertionError();
      }
    }

    @java.lang.Override
    @java.lang.SuppressWarnings("unchecked")
    public io.grpc.stub.StreamObserver<Req> invoke(
        io.grpc.stub.StreamObserver<Resp> responseObserver) {
      switch (methodId) {
        case METHODID_GET_ADS:
          return (io.grpc.stub.StreamObserver<Req>) serviceImpl.getAds(
              (io.grpc.stub.StreamObserver<ads.Ads.AdsList>) responseObserver);
        default:
          throw new AssertionError();
      }
    }
  }

  public static final io.grpc.ServerServiceDefinition bindService(AsyncService service) {
    return io.grpc.ServerServiceDefinition.builder(getServiceDescriptor())
        .addMethod(
          getGetAdsMethod(),
          io.grpc.stub.ServerCalls.asyncBidiStreamingCall(
            new MethodHandlers<
              ads.Ads.Context,
              ads.Ads.AdsList>(
                service, METHODID_GET_ADS)))
        .build();
  }

  private static abstract class AdsServiceBaseDescriptorSupplier
      implements io.grpc.protobuf.ProtoFileDescriptorSupplier, io.grpc.protobuf.ProtoServiceDescriptorSupplier {
    AdsServiceBaseDescriptorSupplier() {}

    @java.lang.Override
    public com.google.protobuf.Descriptors.FileDescriptor getFileDescriptor() {
      return ads.Ads.getDescriptor();
    }

    @java.lang.Override
    public com.google.protobuf.Descriptors.ServiceDescriptor getServiceDescriptor() {
      return getFileDescriptor().findServiceByName("AdsService");
    }
  }

  private static final class AdsServiceFileDescriptorSupplier
      extends AdsServiceBaseDescriptorSupplier {
    AdsServiceFileDescriptorSupplier() {}
  }

  private static final class AdsServiceMethodDescriptorSupplier
      extends AdsServiceBaseDescriptorSupplier
      implements io.grpc.protobuf.ProtoMethodDescriptorSupplier {
    private final java.lang.String methodName;

    AdsServiceMethodDescriptorSupplier(java.lang.String methodName) {
      this.methodName = methodName;
    }

    @java.lang.Override
    public com.google.protobuf.Descriptors.MethodDescriptor getMethodDescriptor() {
      return getServiceDescriptor().findMethodByName(methodName);
    }
  }

  private static volatile io.grpc.ServiceDescriptor serviceDescriptor;

  public static io.grpc.ServiceDescriptor getServiceDescriptor() {
    io.grpc.ServiceDescriptor result = serviceDescriptor;
    if (result == null) {
      synchronized (AdsServiceGrpc.class) {
        result = serviceDescriptor;
        if (result == null) {
          serviceDescriptor = result = io.grpc.ServiceDescriptor.newBuilder(SERVICE_NAME)
              .setSchemaDescriptor(new AdsServiceFileDescriptorSupplier())
              .addMethod(getGetAdsMethod())
              .build();
        }
      }
    }
    return result;
  }
}
