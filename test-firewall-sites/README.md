# Firewall Sites Testing Script

This script is designed to test connectivity to a list of predefined sites by performing multiple `curl` requests. It captures HTTP response codes and SSL verification results, providing a summary of the results for each site.

## Features

- Perform multiple `curl` requests to test connectivity to a list of sites.
- Capture and count HTTP response codes.
- Capture and count SSL verification results.
- Supports verbose mode for detailed output.
- Redirects output to a log file if specified.
- Displays a summary of results for each site.

## Usage

```bash
[test.sh](http://_vscodecontentref_/0) [options]
```

## Options

-n, --num-requests <number>
Specify the number of curl requests to perform for each site (default: 5).

-v, --verbose
Enable verbose mode for curl to display detailed request and response information.

-o, --output-file <file>
Write output to a specified file instead of only displaying it in the terminal.

-h, --help
Display the help message with usage instructions.

## Example Usage
Run the script with default settings:

```bash
./test.sh
```

Perform 10 requests per site:

```bash
./test.sh -n 10
```

Enable verbose mode:
```bash
./test.sh -v
```

Save output to a file:

```bash
./test.sh -o results.log
```

Display help:

```bash
./test.sh -h
```

## Output
The script outputs the following information for each site:

A banner indicating the site being tested.
HTTP response codes and their counts.
SSL verification results and their counts.

### Example Output

```bash
========================================
          Testing site: quay.io          
========================================
Req 1 to quay.io
Response 1 to quay.io: code 200
Req 2 to quay.io
Response 2 to quay.io: code 200

HTTP code counts for quay.io:
  200: 2

SSL code counts for quay.io:
  0: 2
```

## Requirements
- Bash shell
- curl command-line tool

## Notes

- The script uses associative arrays, which require Bash version 4.0 or later. If you're using macOS, ensure you have an updated version of Bash installed (e.g., via Homebrew).
- The list of sites to test is predefined in the script. You can modify the sites array to include additional sites.