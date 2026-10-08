/* Reproducer: with a long text laid out, each edit to the text storage
   costs time in proportion to the whole text, because GSLayoutManager's
   -_sanityChecks walks every glyph run on each glyph invalidation.

   Builds a text of N lines whose fonts alternate (so each line is its own
   attribute run, with only two distinct attribute dictionaries), puts it
   in an NSTextStorage / NSLayoutManager / NSTextContainer, and times
   two things:

   - layout: -glyphRangeForTextContainer:, which lays out the whole text;
   - edits: with the text laid out, setting each line's attributes again
     to the ones it already has, one line at a time (each edit invalidates
     that line's glyphs; nothing visible changes).

   Prints one line per N; N doubles each time.

   Build, with the compiler your GNUstep was built with (cc below):
     cc `gnustep-config --objc-flags` 1-libs-gui-layout-sanity-checks.m \
       `gnustep-config --gui-libs` -o layout-repro
   Run:
     ./layout-repro [max-lines]      (default 16000)
*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

static NSTextStorage *
makeText(unsigned lines, NSDictionary *plain, NSDictionary *bold)
{
  NSTextStorage *text = [[NSTextStorage alloc] init];
  unsigned i;

  [text beginEditing];
  for (i = 0; i < lines; i++)
    {
      NSString *line;
      NSAttributedString *piece;

      line = [NSString stringWithFormat:
        @"Line %u of the document, long enough to look like prose.\n", i];
      piece = [[NSAttributedString alloc] initWithString: line
        attributes: (i % 2 ? bold : plain)];
      [text appendAttributedString: piece];
      [piece release];
    }
  [text endEditing];
  return [text autorelease];
}

static void
timeLayoutAndEdits(NSTextStorage *text, NSDictionary *plain,
  NSDictionary *bold, double *layoutSeconds, double *editSeconds)
{
  NSLayoutManager *layout = [[NSLayoutManager alloc] init];
  NSTextContainer *container;
  NSString *string = [text string];
  NSUInteger length = [string length];
  NSUInteger location = 0;
  unsigned i = 0;
  NSDate *start;

  container = [[NSTextContainer alloc]
    initWithContainerSize: NSMakeSize(600, 1.0e7)];
  [layout addTextContainer: container];
  [container release];
  [text addLayoutManager: layout];

  start = [NSDate date];
  [layout glyphRangeForTextContainer: container];
  *layoutSeconds = -[start timeIntervalSinceNow];

  start = [NSDate date];
  while (location < length)
    {
      NSRange line = [string lineRangeForRange: NSMakeRange(location, 0)];

      [text setAttributes: (i % 2 ? bold : plain) range: line];
      location = NSMaxRange(line);
      i++;
    }
  *editSeconds = -[start timeIntervalSinceNow];

  [text removeLayoutManager: layout];
  [layout release];
}

static const char *
ratio(double now, double before)
{
  if (before <= 0.0)
    {
      return "";
    }
  return [[NSString stringWithFormat: @"%.1fx", now / before] UTF8String];
}

int
main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  unsigned max = (argc > 1) ? (unsigned)atoi(argv[1]) : 16000;
  NSDictionary *plain;
  NSDictionary *bold;
  unsigned lines;
  double previousLayout = 0.0;
  double previousEdits = 0.0;

  [NSApplication sharedApplication];
  plain = [NSDictionary dictionaryWithObject: [NSFont userFontOfSize: 12]
                                      forKey: NSFontAttributeName];
  bold = [NSDictionary dictionaryWithObject: [NSFont boldSystemFontOfSize: 12]
                                     forKey: NSFontAttributeName];

  printf("%8s %10s %10s %6s %10s %6s\n",
    "lines", "chars", "layout s", "ratio", "edits s", "ratio");
  for (lines = 1000; lines <= max; lines *= 2)
    {
      NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
      NSTextStorage *text = makeText(lines, plain, bold);
      double layoutSeconds;
      double editSeconds;

      timeLayoutAndEdits(text, plain, bold, &layoutSeconds, &editSeconds);
      printf("%8u %10u %10.3f %6s %10.3f %6s\n", lines,
        (unsigned)[text length], layoutSeconds,
        ratio(layoutSeconds, previousLayout), editSeconds,
        ratio(editSeconds, previousEdits));
      fflush(stdout);
      previousLayout = layoutSeconds;
      previousEdits = editSeconds;
      [inner release];
    }
  [pool release];
  return 0;
}
