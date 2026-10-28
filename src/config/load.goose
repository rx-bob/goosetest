// Project configuration uses a small bounded JSON reader so duplicate keys remain observable.
namespace config;

import src.config.decode;
import src.config.json;
import src.config.model;
import src.platform.filesystem;

let MAX_BYTES = 1048576;

// Loads only <project>/goosetest.json. Missing file means legacy mode.
fn load(configuration: Configuration&, project: u8[:]) -> i32 {
    if configuration.configured || configuration.text.len != 0 || configuration.targets.len != 0 {
        configuration.error = "configuration storage must be empty";
        return 2;
    }
    let fd = filesystem::open_project(project);
    if fd < 0 {
        configuration.error = "cannot open project directory";
        configuration.field = "goosetest.json";
        return 2;
    }
    let kind = filesystem::kind(fd, "goosetest.json");
    if filesystem::missing(kind) != 0 {
        let closed = filesystem::close_project(fd);
        if closed < 0 {
            configuration.error = "cannot close project directory";
            return 2;
        }
        return 0;
    }
    if kind != filesystem::FILE {
        configuration.error = "configuration must be a regular file";
        configuration.field = "goosetest.json";
        filesystem::close_project(fd);
        return 2;
    }
    var source: u8[>..] = [];
    let read_result = filesystem::read(fd, "goosetest.json", source, MAX_BYTES);
    let close_result = filesystem::close_project(fd);
    if read_result == filesystem::READ_LIMIT {
        configuration.error = "configuration exceeds 1048576 bytes";
        configuration.field = "goosetest.json";
        return 2;
    }
    if read_result < 0 || close_result < 0 {
        configuration.error = "cannot read configuration file";
        configuration.field = "goosetest.json";
        return 2;
    }
    var tokens: JsonToken[>..] = [];
    var reader = Reader {
        source: source,
        text: configuration.text,
        tokens: tokens
    };
    parse_document(reader);
    if reader.error.len > 0 {
        let offset = configuration.text.len;
        configuration.text.append(reader.error);
        configuration.error = configuration.text[offset..];
        configuration.field = "goosetest.json";
        return 2;
    }
    if !decode_configuration(configuration, reader.tokens) {
        return 2;
    }
    configuration.configured = true;
    return 0;
}
