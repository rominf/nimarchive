import os, strutils, strformat

import nimterop/[build, cimport]

static:
  cDebug()

const
  baseDir = getProjectCacheDir("nimarchive" / "libarchive")

  defs = """
    archiveStatic
    archiveDL
    archiveSetVer=3.4.0

    bzlibStatic
    bzlibStd
    bzlibConan
    bzlibSetVer=1.0.8

    lzmaStatic
    lzmaStd
    lzmaConan
    lzmaSetVer=5.2.4

    zlibStatic
    zlibStd
    zlibConan
    zlibSetVer=1.2.11
  """

setDefines(defs.splitLines())

import bzlib, lzma, zlib

const
  llp = lzmaLPath.sanitizePath(sep = "/")
  zlp = zlibLPath.sanitizePath(sep = "/")
  blp = bzlibLPath.sanitizePath(sep = "/")

  conFlags =
    flagBuild("--without-$#",
      ["lzma", "zlib", "bz2lib", "nettle", "openssl", "libb2", "lz4", "zstd", "xml2", "expat"]
    ) &
    flagBuild("--disable-$#",
      ["bsdtar", "bsdcat", "bsdcpio", "acl"]
    )

  cmakeFlags =
    getCmakeIncludePath([lzmaPath.parentDir(), zlibPath.parentDir(), bzlibPath.parentDir()]) &
    &" -DLIBLZMA_LIBRARY={llp} -DZLIB_LIBRARY={zlp} -DBZIP2_LIBRARY_RELEASE={blp}" &
    flagBuild("-DENABLE_$#=OFF",
      ["NETTLE", "OPENSSL", "LIBB2", "LZ4", "ZSTD", "LIBXML2", "EXPAT", "TEST", "TAR", "CAT", "CPIO", "ACL"]
    )

proc archivePreBuild(outdir, path: string) =
  putEnv("CFLAGS", "-DHAVE_LIBLZMA=1 -DHAVE_LZMA_H=1" &
    " -DHAVE_LIBBZ2=1 -DHAVE_BZLIB_H=1" &
    " -DHAVE_LIBZ=1 -DHAVE_ZLIB_H=1 -I" &
    lzmaPath.parentDir().replace("\\", "/").replace("C:", "/c") & " -I" &
    zlibPath.parentDir().replace("\\", "/").replace("C:", "/c") & " -I" &
    bzlibPath.parentDir().replace("\\", "/").replace("C:", "/c"))
  putEnv("LIBS", &"{llp} {zlp} {blp}")

  let
    lcm = outdir / "libarchive" / "CMakeLists.txt"
  if lcm.fileExists():
    var
      lcmd = lcm.readFile()
    lcmd = lcmd.multiReplace([
      ("ADD_LIBRARY(archive SHARED ${libarchive_SOURCES} ${include_HEADERS})", ""),
      ("TARGET_INCLUDE_DIRECTORIES(archive PUBLIC .)", ""),
      ("TARGET_LINK_LIBRARIES(archive ${ADDITIONAL_LIBS})", ""),
      ("SET_TARGET_PROPERTIES(archive PROPERTIES SOVERSION ${SOVERSION})", ""),
      ("archive archive_static", "archive_static")
    ])
    lcm.writeFile(lcmd)

getHeader(
  header = "archive.h",
  giturl = "https://github.com/libarchive/libarchive",
  dlurl = "https://libarchive.org/downloads/libarchive-$1.zip",
  outdir = baseDir,
  conFlags = conFlags,
  cmakeFlags = cmakeFlags
)

cPlugin:
  import strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    sym.name = sym.name.strip(chars={'_'}).replace("___", "_")

cOverride:
  type
    stat* {.importc: "struct stat", header: "sys/stat.h".} = object
    dev_t* = int32
    mode_t* = uint32

type
  LA_MODE_T = int

when defined(windows):
  {.passL: "-lbcrypt".}

  cOverride:
    type
      BY_HANDLE_FILE_INFORMATION* = object

static:
  cSkipSymbol(@["archive_read_open_file", "archive_write_open_file"])

let
  archiveEntryPath {.compileTime.} = archivePath[0 .. ^3] & "_entry.h"

when archiveStatic:
  cImport(@[archivePath, archiveEntryPath], recurse = true, flags = "-f:ast2")
  {.passL: bzlibLPath.}
  {.passL: lzmaLPath.}
  {.passL: zlibLPath.}
  when defined(osx):
    {.passL: "-liconv".}
else:
  cImport(@[archivePath, archiveEntryPath], recurse = true, dynlib = "archiveLPath", flags = "-f:ast2")
