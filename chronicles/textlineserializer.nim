import
  times,
  strutils,
  terminal,
  system,
  options

import
  serialization,
  faststreams/[outputs, textio]

import
  chronicles,
  options

type
  TextLineWriter*[timeFormat: static[TimestampsScheme], colorScheme: static[ColorScheme]] = object
    stream: OutputStream
    currentLevel: LogLevel

  TextLineReader* = object
    lexer: string

serializationFormat TextLine,
                    Reader = TextLineReader,
                    Writer = TextLineWriter,
                    PreferedOutput = string,
                    mimeType = "text/plain"

#
# value support functions
#

const
  escChars: set[char] = strutils.NewLines + {'"', '\\'}
  quoteChars: set[char] = {' ', '='}

proc quoteIfNeeded(w: var TextLineWriter, val: SomeOrdinal) =
  w.stream.writeText val

proc quoteIfNeeded(w: var TextLineWriter, val: auto) =
  let valText = $val
  let
    needsEscape = valText.find(escChars) > -1
    needsQuote = (valText.find(quoteChars) > -1) or needsEscape
  if needsQuote:
    var quoted = ""
    quoted.addQuoted valText
    w.stream.writeText quoted
  else:
    w.stream.writeText val

proc quoteIfNeeded(w: var TextLineWriter, val: ref Exception) =
  w.stream.writeText val.name
  w.stream.writeText '('
  w.quoteIfNeeded val.msg
  when not defined(js) and not defined(nimscript) and hostOS != "standalone":
    w.stream.writeText ", "
    w.quoteIfNeeded getStackTrace(val).strip
  w.stream.writeText ')'

#
# Class startup
#

proc init*(w: var TextLineWriter, stream: OutputStream) =
  w.stream = stream

#
# Field Handling
#

proc writeFieldName*(w: var TextLineWriter, name: string) =
  w.stream.writeText ' '
  let (color, bright) = levelToStyle(w.currentLevel)
  setForegroundColor(w, color, bright)
  w.stream.writeText name
  resetAllColors(w)
  w.stream.writeText "="

proc writeValue*(w: var TextLineWriter, value: auto) =
  setForegroundColor(w, propColor, true)
  w.quoteIfNeeded(value)
  resetAllColors(w)

proc writeArray*[T](w: var TextLineWriter, elements: openarray[T]) =
  w.stream.writeText '['
  let clen = elements.len - 1
  for index, value in elements.pairs:
    w.stream.writeText value
    if index < clen:
      w.stream.writeText ", "
  w.stream.writeText ']'

proc writeIterable*(w: var TextLineWriter, collection: auto) =
  w.stream.writeText '['
  let clen = collection.len - 1
  for index, value in collection.pairs:
    w.stream.writeText value
    if index < clen:
      w.stream.writeText ", "
  w.stream.writeText ']'

proc writeField*(w: var TextLineWriter, name: string, value: auto) =
  writeFieldName(w, name)
  writeValue(w, value)

# template endRecordField*(w: var TextLineWriter) =
#   discard

#
# Record Handling
#
proc beginRecord*(w: var TextLineWriter, level: LogLevel, topics, title: string) =
  w.currentLevel = level
  let (logColor, logBright) = levelToStyle(level)
  setForegroundColor(w, logColor, logBright)
  w.stream.writeText shortName(w.currentLevel)
  resetAllColors(w)
  when w.timeFormat == UnixTime:
    w.stream.writeText ' '
    w.stream.writeText formatFloat(epochTime(), ffDecimal, 6)
  when w.timeFormat == RfcTime:
    w.stream.writeText now().format(" yyyy-MM-dd HH:mm:sszzz")
  let titleLen = title.len
  if titleLen > 0:
    w.stream.writeText ' '
    applyColorStyle(w, styleBright)
    if titleLen > 42:
      w.stream.writetext title
    else:
      for index in 0 ..< 42:
        if index < titleLen:
          w.stream.writeText title[index]
        else:
          w.stream.writeText ' '
    resetAllColors(w)
  if topics.len > 0:
    w.stream.writeText " topics=\""
    setForegroundColor(w, topicsColor, true)
    w.stream.writeText topics
    resetAllColors(w)
    w.stream.writeText '"'

proc endRecord*(w: var TextLineWriter) =
  w.stream.write '\n'

proc getStream*(w: var TextLineWriter): OutputStream =
  result = w.stream
