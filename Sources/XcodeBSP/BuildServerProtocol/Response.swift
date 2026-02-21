struct Response<Result>: Encodable where Result: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONRPCID
    let result: Result
}
