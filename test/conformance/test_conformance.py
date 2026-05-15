from pathlib import Path

from hegel.conformance import (
    IntegerConformance,
    run_conformance_tests,
    BooleanConformance,
    FloatConformance,
    TextConformance,
    BinaryConformance,
    ListConformance,
    SampledFromConformance,
    DictConformance,
    StopTestOnGenerateConformance,
    StopTestOnMarkCompleteConformance,
    ErrorResponseConformance,
    EmptyTestConformance,
    StopTestOnCollectionMoreConformance,
    StopTestOnNewCollectionConformance,
    OneOfConformance,
    OriginDeduplicationConformance,
)

BUILD_DIR = Path(__file__).parent.parent.parent / "build" / "conformance"


BIGINT_MIN = -(2**128)
BIGINT_MAX = 2**128


def test_conformance(subtests):
    run_conformance_tests(
        [
            IntegerConformance(
                BUILD_DIR / "test_integers", min_value=BIGINT_MIN, max_value=BIGINT_MAX
            ),
            BooleanConformance(BUILD_DIR / "test_booleans"),
            FloatConformance(BUILD_DIR / "test_floats"),
        ],
        subtests,
        skip_tests=[
            BinaryConformance,
            DictConformance,
            EmptyTestConformance,
            ErrorResponseConformance,
            ListConformance,
            OneOfConformance,
            OriginDeduplicationConformance,
            SampledFromConformance,
            StopTestOnCollectionMoreConformance,
            StopTestOnGenerateConformance,
            StopTestOnMarkCompleteConformance,
            StopTestOnNewCollectionConformance,
            TextConformance,
        ],
    )
