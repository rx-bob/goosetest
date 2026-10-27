// Independent renderer checks use builtin assertions rather than rendered verdicts.
import goosetest from "..";

import reporting.console_test;
import reporting.formatting_test;

fn main() {
    formatting_test::test_labels();
    formatting_test::test_escaping();
    formatting_test::test_chunk_bound();
    console_test::test_case_order_and_totals();
    console_test::test_reused_id_order();
    console_test::test_active_and_incomplete();
    console_test::test_runner_error_record();
}
