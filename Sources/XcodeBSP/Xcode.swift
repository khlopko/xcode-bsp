struct XcodeBuildSettings: Decodable {
    let target: String
    let action: String
    let buildSettings: BuildSettings

    struct BuildSettings: Decodable {
        let BUILD_DIR: String
        let BUILD_ROOT: String
        let PROJECT: String
        let SOURCE_ROOT: String
    }
}
