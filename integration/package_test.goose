// Independent oracle: parent supplies captured child output and actual process status.
// No import of goosetest; builtin assertions determine whether verification succeeds.
import os;

fn main() {
    assert(arg_count() == 4);
    var output_path: u8[>..] = [];
    var status: u8[>..] = [];
    var variant: u8[>..] = [];
    arg(1, output_path);
    arg(2, status);
    arg(3, variant);
    assert(variant == "passing" || variant == "failing");
    var output: u8[>..] = [];
    assert(read_file(output_path, output));
    if variant == "passing" {
        assert(status == "0");
        assert(output == embed_file("fixtures/package/passing.stdout"));
    } else {
        assert(status == "1");
        assert(output == embed_file("fixtures/package/failing.stdout"));
    }
}
