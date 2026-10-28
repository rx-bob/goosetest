// Publish dependencies before the generated entry, retaining ownership across interrupted writes.
namespace artifacts;

import src.generation.model;
import src.platform.staging;

fn publish(fd: i32, output: generation::Output&, target_name: u8[:] = "") -> i32 {
    if generation::status(output) != 0 {
        return -1;
    }
    var names: u8[>..] = [];
    let runner_path: u8[>..] = if target_name.len == 0 {
        "runner.goose"
    } else {
        str(target_name, "/runner.goose")
    };
    for module in output.modules {
        names.append(generation::module_path(output, module));
        names.push('\n');
    }
    let prepared = staging::prepare(fd, names);
    if prepared != 0 {
        return prepared;
    }
    for module in output.modules {
        if generation::module_path(output, module) != runner_path {
            let error = write_module(fd, output, module);
            if error != 0 {
                return error;
            }
        }
    }
    for module in output.modules {
        if generation::module_path(output, module) == runner_path {
            let error = write_module(fd, output, module);
            if error != 0 {
                return error;
            }
        }
    }
    return staging::finish(fd, names);
}

fn write_module(fd: i32, output: generation::Output&, module: generation::Module) -> i32 {
    return staging::write(fd, generation::module_path(output, module), generation::module_source(output, module));
}
