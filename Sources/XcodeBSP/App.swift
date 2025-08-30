@main
struct XcodeBSPApp {
    static func main() throws {
        let server = try XcodeBuildServer()
        try server.run()
    }
}

