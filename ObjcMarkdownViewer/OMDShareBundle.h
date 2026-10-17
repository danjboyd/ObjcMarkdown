// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <Foundation/Foundation.h>

// The CRC-32 a .zip records for data (IEEE 802.3, as zlib's crc32()).
uint32_t OMDShareCRC32(NSData *data);

// Writes a .zip of stored (uncompressed) entries: names (UTF-8, "/"
// between folders) in order, each with its NSData in contents. Images are
// compressed already, so storing costs little and needs no zlib on any
// platform. NO if the file can't be written.
BOOL OMDShareWriteZip(NSString *path, NSArray *names, NSArray *contents);

// The Markdown with its local images for a .zip bundle (#190): the
// document as "<baseName>/<baseName>.md" and each image that exists. An
// image in the document's folder keeps its relative path; one elsewhere
// (an absolute path, a file: URL, "../") is put in images/ and its
// reference in the Markdown rewritten. Images that can't be found are left
// out and their references kept. Fills names and contents for
// OMDShareWriteZip().
void OMDShareBundleEntries(NSString *markdown,
                           NSString *baseDirectory,
                           NSString *baseName,
                           NSMutableArray *names,
                           NSMutableArray *contents);
