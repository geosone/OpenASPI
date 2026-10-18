# Shared DOS driver support

This directory will hold request-header definitions, status/error conversion,
resident initialization helpers, command-line parsing, and device-header
support shared by the four DOS drivers.

Block, CD-ROM and character drivers have different DOS contracts; common code
must not erase those distinctions.
