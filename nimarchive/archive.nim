import os, strutils, strformat

import nimterop/[build, cimport]

const
  defs = """
    archiveStatic
    archiveDL
    archiveSetVer=3.4.0

    bzlibStatic
    bzlibDL
    bzlibSetVer=1.0.8

    lzmaStatic
    lzmaDL
    lzmaSetVer=5.2.4

    zlibStatic
    zlibDL
    zlibSetVer=1.2.11
  """

setDefines(defs.splitLines())

import bzlib, lzma, zlib

const
  baseDir = currentSourcePath.parentDir() / "build" / "libarchive"

static:
  cDebug()

const
  conFlags = block:
    var cf =
      flagBuild("--without-$#",
        ["lzma", "zlib", "bz2lib", "nettle", "openssl", "libb2", "lz4", "zstd", "xml2", "expat"]
      ) &
      flagBuild("--disable-$#",
        ["bsdtar", "bsdcat", "bsdcpio", "acl"]
      )
    cf

  cmakeFlags = block:
    let
      llp = lzmaLPath.sanitizePath(sep = "/")
      zlp = zlibLPath.sanitizePath(sep = "/")
      blp = bzlibLPath.sanitizePath(sep = "/")
    var cf =
      getCmakeIncludePath([lzmaPath.parentDir(), zlibPath.parentDir(), bzlibPath.parentDir()]) &
      &" -DLIBLZMA_LIBRARY={llp} -DZLIB_LIBRARY={zlp} -DBZIP2_LIBRARY_RELEASE={blp}" &
      flagBuild("-DENABLE_$#=OFF",
        ["NETTLE", "OPENSSL", "LIBB2", "LZ4", "ZSTD", "LIBXML2", "EXPAT", "TEST", "TAR", "CAT", "CPIO", "ACL"]
      )
    cf

proc archivePreBuild(outdir, path: string) =
  putEnv("CFLAGS", "-DHAVE_LIBLZMA=1 -DHAVE_LZMA_H=1 -DHAVE_LIBZ=1 -DHAVE_ZLIB_H=1 -I" &
    lzmaPath.parentDir().replace("\\", "/").replace("C:", "/c") & " -I" &
    zlibPath.parentDir().replace("\\", "/").replace("C:", "/c"))
  let
    rf = readFile(path)
    str = "\n#include \"archive_entry.h\"\n"
  if not rf.contains(str):
    writeFile(path, rf & str)

getHeader(
  "archive.h",
  "https://github.com/libarchive/libarchive",
  "https://libarchive.org/downloads/libarchive-$1.zip",
  outdir = baseDir,
  conFlags = conFlags,
  cmakeFlags = cmakeFlags
)

cPlugin:
  import strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    if sym.kind in [nskParam]:
      sym.name = sym.name.strip(chars={'_'})

cOverride:
  type
    stat* {.importc: "struct stat", header: "sys/stat.h".} = object
    dev_t* = int32
    mode_t* = uint32

  when defined(windows):
    type
      BY_HANDLE_FILE_INFORMATION* = object

    {.passL: "-lbcrypt".}

static:
  cSkipSymbol(@["archive_read_open_file", "archive_write_open_file"])

when archiveStatic:
  cImport(archivePath, recurse = true)
  {.passL: bzlibLPath.}
  {.passL: lzmaLPath.}
  {.passL: zlibLPath.}
  when defined(osx):
    {.passL: "-liconv".}
else:
  cImport(archivePath, recurse = true, dynlib = "archiveLPath")