@main
struct XcodeBSPApp {
    static func main() throws {
        let server = try XcodeBuildServer()
        server.run()
    }
}

