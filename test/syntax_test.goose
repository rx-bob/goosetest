// Independent bootstrap syntax suite; source parsing needs no native adapter.
import goosetest from "..";

import std;

import discovery.annotations_test;
import discovery.catalog_test;
import discovery.declarations_test;
import discovery.lexer_test;
import discovery.manifest_test;
import discovery.signatures_test;
import discovery.syntax_errors_test;

fn main() {
    lexer_test::test_locations();
    lexer_test::test_groups();
    lexer_test::test_lexical_errors();
    lexer_test::test_literal_decoys();
    lexer_test::test_lexer_limits();
    declarations_test::test_authoring();
    declarations_test::test_namespace_and_fixture_errors();
    declarations_test::test_late_fixture_and_crlf();
    declarations_test::test_owned_names();
    signatures_test::test_bad_parameters();
    signatures_test::test_unsupported_modifiers();
    signatures_test::test_hook_signatures();
    annotations_test::test_bad_annotations();
    annotations_test::test_orphans();
    annotations_test::test_metadata_escapes();
    catalog_test::test_duplicates();
    catalog_test::test_labels_do_not_define_identity();
    catalog_test::test_empty_manifest();
    syntax_errors_test::test_location_diagnostic();
    catalog_test::test_inventory_selection();
    catalog_test::test_strict_suite_files();
    catalog_test::test_disabled_suite_is_nonempty();
    manifest_test::test_case_and_suite_limits();
    manifest_test::test_byte_limits();
    manifest_test::test_text_limits();
    manifest_test::test_invalid_limits();
    print("syntax tests passed");
}
