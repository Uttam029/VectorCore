import datetime

class Logger:
    """Simple file logger for simulation traces.
    
    Writes all simulation output to a timestamped log file in test/logs/.
    Supports two levels:
      - debug: Detailed per-cycle execution traces
      - info:  Summary information (memory states, cycle counts)
    """
    def __init__(self, level="debug"):
        self.filename = f"test/logs/log_{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}.txt"
        self.level = level

    def debug(self, *messages):
        """Log debug-level messages (detailed execution traces)."""
        if self.level == "debug":
            self.info(*messages)

    def info(self, *messages):
        """Log info-level messages (always written)."""
        full_message = ' '.join(str(message) for message in messages)
        with open(self.filename, "a") as log_file:
            log_file.write(full_message + "\n")

# Global logger instance used by all test modules
logger = Logger(level="debug")
