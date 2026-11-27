"""AWS Batch entry point: convert one file, then exit.

Batch runs: uv run python batch_convert.py <cloud_file_id>
It reuses the Celery task's code, called in this process (no broker, no worker).
"""

import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from tasks.cpu import convert_file  # noqa: E402

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s"
)


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] in ("", "none"):
        logging.error("Usage: batch_convert.py <cloud_file_id>")
        return 2
    # Pipeline test marker: proves Batch runs the image from the latest pipeline run.
    logging.info("PIPELINE TEST v1: batch job started for %s", sys.argv[1])
    result = convert_file(sys.argv[1])
    logging.info("Result: %s", result)
    # Non-zero marks the job FAILED in Batch; the row is already set to removed.
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
