# grpc-playground — Bidirectional Streaming Spec

## Objective
Implement a **gRPC bidirectional streaming** playground with both **client** and **server** versions written in **Java**, **C++**, and **Rust**.

## Repository Layout
```
grpc-playground/
  docs/spec.md
  proto/ads.proto
  client/
    java/
    cpp/
    rust/
  server/
    java/
    cpp/
    rust/
```

## Protocol (proto3 sketch)
```proto
syntax = "proto3";
package ads;

message Context {
  string query = 1;          // e.g., "coffee maker"
  string asin_id = 2;        // e.g., "B000123"
  string understanding = 3;  // empty on first send, filled on second
}

message Ad {
  string asin_id = 1;
  string ad_id = 2;
  double score = 3;
}

message AdsList {
  repeated Ad ads = 1;
  uint32 version = 2; // 1, 2, 3 to reflect stream updates
}

service AdsService {
  rpc GetAds(stream Context) returns (stream AdsList);
}
```

## Interaction Timeline
1. **Client opens stream** `GetAds()`.
2. **Client message #1** (`onNext`): `Context{query, asin_id, understanding=""}`.
3. **Server message #1** (`onNext`): `AdsList{version=1}`, generated using the base `Context`.
4. **Client message #2** (`onNext`): `Context{query, asin_id, understanding=<filled>}`.  
   - Sent **50 ms** after message #1.  
   - Client then calls `onCompleted` to **half-close** its side of the stream.
5. **Server message #2** (`onNext`): `AdsList{version=2}`, generated using the full `Context` (replaces v1).
6. **~50 ms later**: **Server message #3** (`onNext`): `AdsList{version=3}`, a final refinement (replaces v2).
7. **Server completes** the response stream (`onCompleted`).  
8. **Client logic**: waits a **random timeout window** (30–120 ms, jittered). The most recent `AdsList` available at that moment is treated as the **final result**.  
9. **Client logging**: log whether an `AdsList` was received before timeout and which version was selected.

## Client Behavior
- Send exactly **two** `Context` messages on the same stream (no new RPC).  
- After the second `Context`, half-close the stream (`onCompleted`).  
- Buffer the latest `AdsList` by `version` and expose the most recent as the final result.  
- Handle out-of-order arrival defensively (use `version` to replace older results).  

## Server Behavior
- For each inbound `Context`, emit an `AdsList` that replaces the previous one.  
- After the second `Context`, schedule a **third** `AdsList` about **50 ms** later.  
- After sending the third list, complete the stream (`onCompleted`).  

## Acceptance Criteria
- All six language targets (Java/C++/Rust for client and server) interoperate consistently.  
- Exactly **2** `Context` messages from the client and **3** `AdsList` messages from the server per call.  
- Client returns the `AdsList` matching the **latest version** observed within its decision window.  
- Graceful shutdown: no dangling streams, deadlines respected, and errors surfaced properly.  

---

## Step-by-Step Plan
1. **Define proto** (`proto/ads.proto`) and generate code for all languages.  
2. **Implement servers** (Java/C++/Rust):  
   - Mock ad generation (e.g., 5–10 ads with scores).  
   - Emit v1 on first `Context`, v2 on second, schedule v3 after 50 ms, then complete.  
3. **Implement clients** (Java/C++/Rust):  
   - Open bidi stream, send first `Context`, then second (after 50 ms).  
   - Half-close after the second send.  
   - Buffer responses by `version` and return the latest after random wait.  
4. **Interop tests**:  
   - Run each client against each server.  
   - Verify counts (2 in, 3 out), ordering by version, and correct final selection.  
5. **Developer Experience (DX) polish**:  
   - Scripts for codegen, build, and execution.  

Ask clarification questions before start coding.
Ask questions if there is design decisions need to be made.
Take step-by-step approach.
