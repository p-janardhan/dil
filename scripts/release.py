#! /usr/bin/python
# -*- coding: utf-8 -*-
# Author: Aziz Köksal
# License: zlib/libpng
#
# This is the script that creates release packages for DIL.
#
from __future__ import unicode_literals, print_function
from common import *
from build import DMDCommand, LDCCommand
from targets import *
from html2pdf import PDFGenerator
from html2chm import CHMGenerator
__file__ = tounicode(__file__)

def copy_files(DIL):
  """ Copies required files to the destination folder. """
  Paths(DIL.DATA/"html.css",  DIL.DOC.HTMLSRC).copy(\
       (DIL.KANDIL.style,     DIL.DOC.CSS))
  DIL.KANDIL.jsfiles.copy(DIL.DOC.JS)
  DIL.KANDIL.images.copy(DIL.DOC.IMG)

def writeMakefile():
  """ Writes a Makefile for building DIL. """
  # TODO: implement.
  pass

def write_modified_dilconf(SRC, DEST, DATADIR):
  DEST.write(re.sub('DATADIR = ".+?"', 'DATADIR = "%s"' % DATADIR, SRC.read()))

def get_totalsize_and_md5sums(FILES, root_index):
  from md5 import new as md5
  totalsize = 0
  md5sums = ""
  for f in FILES:
    totalsize += f.size
    data = f.read(encoding=None)
    checksum = md5(data).hexdigest()
    md5sums += "%s  %s\n" % (checksum, f[root_index + 1:])
  return (totalsize/1024, md5sums)

def make_deb_package(SRC, DEST, VERSION, ARCH, TMP, MAINTAINER, PACKAGENUM=1):
  BINSFX = '-'+VERSION.BINSFX if VERSION.BINSFX else ''
  dil = "dil"+BINSFX # Package name, binaries prefix, dir name, etc.

  # 1. Create folders.
  TMP = (TMP/"debian").mkdir() # The root folder.
  BIN = (TMP/"usr"/"bin").mkdir()
  DOC = (TMP/"usr"/"share"/"doc"/dil).mkdir()
  MAN = (TMP/"usr"/"share"/"man"/"man1").mkdir()
  SHR = (TMP/"usr"/"share"/dil).mkdir()
  ETC = (TMP/"etc").mkdir()
  DEBIAN = (TMP/"DEBIAN").mkdir()

  # 2. Copy DIL's files.
  for binary in SRC.BINS:
    binary.copy(BIN/(dil+binary.name[3:])) # Copy and rename binaries.
  write_modified_dilconf(SRC.DATA/"dilconf.d", ETC/"dilconf.d",
    SHR[len(TMP):] + "/data")
  copyright = "License: GPL3\nAuthors: See AUTHORS file.\n"
  (DOC/"copyright").write(copyright)
  CLOG = DOC/"changelog"
  CLOG.write("\n")
  CLOGDEB = DOC/"changelog.Debian"
  CLOGDEB.write("\n")
  (SRC/"AUTHORS").copy(DOC)
  SRC.DATA.copy(SHR/"data")
  if SRC.DOC.exists:
    SRC.DOC.copy(DOC/"api")
  MANPAGE = MAN/"%s.1" % dil
  MANPAGE.write("\n")
  for f in (MANPAGE, CLOG, CLOGDEB):
    call_proc("gzip", "--best", f)
  (MANPAGE+".gz").copy(MAN/"%s_dbg.1.gz" % dil)

  # 3. Get all package files excluding the special DEBIAN folder.
  FILES = TMP.rxglob(".", prunedir=lambda p: p.name == "DEBIAN")

  # 4. Generate package files.
  SIZE, md5sums = get_totalsize_and_md5sums(FILES, len(TMP))

  # Replace the dash with a dot, because there may be a suffix.
  VERSION = VERSION.replace("-", ".")

  control = """Package: {dil}
Version: {VERSION}-{PACKAGENUM}
Section: devel
Priority: optional
Architecture: {ARCH}
Depends: libc6
Provides: d-compiler
Installed-Size: {SIZE}
Maintainer: {MAINTAINER}
Bugs: https://github.com/azizk/dil/issues
Homepage: http://code.google.com/p/dil
Description: D compiler
 DIL is a feature-rich compiler for the D programming language
 written entirely in D.
"""
  control = control.format(**locals())

  conffiles = "/etc/dilconf.d\n"

  # 5. Write the special files.
  (DEBIAN/"control").write(control)
  (DEBIAN/"conffiles").write(conffiles)
  (DEBIAN/"md5sums").write(md5sums)
  SCRIPTS = DEBIAN/("postinst", "prerm")
  SCRIPTS.write("#!/bin/sh\nexit 0\n") # Write empty scripts for now.

  # 6. Set file/dir permissions.
  ALLDIRS = []
  TMP.rxglob(".", prunedir=lambda p: ALLDIRS.append(p))

  for f in FILES + DEBIAN/("control", "conffiles", "md5sums"):
    call_proc("chmod", "644", f)

  for d in ALLDIRS + BIN.rxglob(".") + SCRIPTS:
    call_proc("chmod", "755", d)

  # 7. Create the package.
  NAME = "{dil}_{VERSION}-{PACKAGENUM}_{ARCH}.deb".format(**locals())
  call_proc("fakeroot", "dpkg-deb", "--build", TMP, DEST/NAME)
  TMP.rm()
  return DEST/NAME

def get_MAINTAINER(M):
  if M == None:
    if locate_command("git"): # Fetch from git if available.
      name_email = [call_read("git", "config", "user."+x)[:-1]
                    for x in ("name", "email")]
      M = "{} <{}>".format(*name_email)
    else:
      M = "Unknown <un@kn.own>"
  if not re.match(r"^.+? <[^>@]+@[^>]+>$", M):
    print("Warning: 'deb package maintainer' seems to be in the wrong format")
  return M


def build_dil(CmdClass, *args, **kwargs):
  cmd = CmdClass(*args, **kwargs)
  print(cmd)
  return cmd.call()

def update_VERSION(path, V):
  """ Updates the version info in the compiler's source code. """
  code = path.read()
  for args in (("MAJOR", V.MAJ), ("MINOR", int(V.MIN)),
               ("SUFFIX", '"%s"' % V.SFX)):
    code = re.sub("(VERSION_%s =).+?;" % args[0], r"\g<1> %s;" % args[1], code)
  path.write(code)

def write_VERSION(VERSION, DEST):
  (DEST/"VERSION").write("%s\n" % VERSION)

def write_PDF(DIL, SRC, VERSION, TMP):
  pdf_gen = PDFGenerator()
  pdf_gen.fetch_files(DIL, TMP)
  html_files = SRC.glob("*.html")
  sym_url = "http://dl.dropbox.com/u/17101773/doc/dil/{0}" # % VERSION

  params = {
    "pdf_title": "DIL %s API" % VERSION,
    "cover_title": "DIL %s<br/><b>API</b>" % VERSION,
    "author": "Aziz Köksal",
    "subject": "Compiler API",
    "keywords": "DIL D compiler API documentation",
    "x_html": "XHTML",
    "nested_toc": True,
    "sym_url": sym_url
  }
  dest = SRC/("dil.%s.API.pdf" % VERSION)
  pdf_gen.run(html_files, dest, TMP, params)

def write_CHM(DIL, SRC, VERSION, TMP):
  TMP = (TMP/"chm").mkdir()

  chm_gen = CHMGenerator()
  chm_gen.fetch_files(DIL.DOC, TMP)
  html_files = SRC.glob("*.html")
  params = {
    "title": "DIL %s API" % VERSION,
    "default_window": "main",
    "default_topic": "dilconf.html",
  }
  dest = SRC/("dil.%s.API.chm" % VERSION)
  chm_gen.run(html_files, dest, TMP, params)

def build_binaries(TARGETS, COMPILER, V_MAJOR, FILES, DEST):
  from functools import partial as func_partial
  CmdClass = COMPILER.CmdClass

  def fix_dirsep(path, target):
    if not is_win32 and target.iswin: # Wine needs Windows-style paths.
      path = path.replace(Path.sep, r"\\")
    return path

  if not is_win32 and any(t.iswin for t in TARGETS) and \
     not locate_command("wine"):
    print("Warning: cannot build Windows binaries: 'wine' is not in PATH.")
    TARGETS = [t for t in TARGETS if not t.iswin]

  # Create a curried build function with common parameters.
  build_binary  = func_partial(build_dil, CmdClass, FILES, exe=COMPILER,
    versions=["D"+V_MAJOR])

  BINS = [] # Successfully compiled binaries.

  for target in TARGETS:
    print("== Building {name} {bits}bit binary ==".format(**target))
    dbgargs = rlsargs = {"m%d" % target.bits : True}
    if target.iswin:
      dbgargs = rlsargs = dict(rlsargs, wine=not is_win32)
    if target.islin:
      dbgargs = dict(rlsargs, lnk_args=["-ltango-dmd", "-lphobos2", "-ldl"])
    # Destination dir for the binary.
    B = (DEST/target.dir/"bin%d"%target.bits).mkdir()
    SFX = "" # An optional suffix. Empty for now.
    DBGEXE, RLSEXE = (B/target[exe] % SFX for exe in ("dbgexe", "rlsexe"))
    dbgargs.update(debug_info=True)
    build_binary(fix_dirsep(DBGEXE, target), **dbgargs)
    # NB: the -inline switch makes the binaries significantly larger on Linux.
    # Enable inlining when DMDBUG #7967 is fixed.
    rlsargs.update(release=True, optimize=True, inline=False)
    build_binary(fix_dirsep(RLSEXE, target), **rlsargs)
    DBGEXE.target = RLSEXE.target = target
    BINS += [exe for exe in (DBGEXE, RLSEXE) if exe.exists]

  return BINS


def main():
  from functools import partial as func_partial
  from argparse import ArgumentParser, SUPPRESS

  parser = ArgumentParser()
  addarg = parser.add_argument
  addflag = func_partial(addarg, action="store_true")
  addarg("version", metavar="VERSION", nargs=1,
    help="the version to be released")
  addflag("-s", "--dsymbols", dest="debug_symbols",
    help="generate debug symbols for debug builds")
  addflag("-d", "--docs", dest="docs", help="generate documentation")
  addflag("-n", "--no-bin", dest="no_binaries", help="don't compile code")
  addflag("--7z", dest="_7z", help="create a 7z archive")
  addflag("--gz", dest="tar_gz", help="create a tar.gz archive")
  addflag("--bz2", dest="tar_bz2", help="create a tar.bz2 archive")
  addflag("--zip", dest="zip", help="create a zip archive")
  addflag("--deb", dest="deb", help="create deb files")
  addflag("--pdf", dest="pdf", help="create a PDF document")
  addflag("--chm", dest="chm", help=SUPPRESS) # "create a CHM file"
  addflag("-m", dest="copy_modified",
    help="copy modified files from the (git) working directory")
  addflag("--ldc", dest="ldc", help="use ldc instead of dmd")
  addarg("--src", dest="src", metavar="SRC",
    help="use SRC folder instead of checking out code with git")
  addarg("--cmp-exe", dest="cmp_exe", metavar="EXE_PATH",
    help="specify EXE_PATH if dmd/ldc is not in your PATH")
  addarg("--builddir", dest="builddir", metavar="DIR",
    help="where to build the release and archives (default is build/)")
  addarg("--winpath", dest="winpath", metavar="P",
    help="permanently append P to PATH in the Windows (or wine's) registry. "
         "Exits the script.")
  addarg("--debm", dest="deb_mntnr", metavar="MTR",
    help=SUPPRESS) # Sets the maintainer info of the package.
  addarg("--debnum", dest="deb_num", metavar="NUM", default=1,
    help=SUPPRESS) # Sets the package number.

  options = args = parser.parse_args(sys.uargv[1:])

  if options.winpath != None:
    from env_path import append2PATH
    append2PATH(options.winpath)
    return

  change_cwd(__file__)

  # Validate the version argument.
  m = re.match(r"^((\d)\.(\d{3})(?:-(\w+))?)(?:\+(\w+))?$", args.version)
  if not m:
    parser.error("invalid VERSION format: /\d.\d\d\d(-\w+)?/ E.g.: 1.123")
  # The version of DIL to be built.
  class Version(unicode):
    def __new__(cls, parts):
      v = unicode.__new__(cls, parts[0])
      v.MAJ, v.MIN, SFX, BSFX = parts[1:]
      v.SFX = SFX or ''
      v.BINSFX = BSFX or ''
      return v
  VERSION = Version(m.groups())

  # Pick a compiler for compiling DIL.
  CmdClass = (DMDCommand, LDCCommand)[options.ldc]
  COMPILER = Path(options.cmp_exe or CmdClass.exe)
  COMPILER.CmdClass = CmdClass
  if not COMPILER.exists and not locate_command(COMPILER):
    parser.error("The executable '%s' could not be located." % COMPILER)

  # Path to DIL's root folder.
  DIL       = dil_path()

  # Build folder.
  BUILDROOT = Path(options.builddir or "build")/("dil_"+VERSION)
  # Destination of distributable files.
  DEST      = dil_path(BUILDROOT/"dil", dilconf=False)
  DEST.DOC  = doc_path(DEST.DOC)

  # Temporary directory, deleted in the end.
  TMP       = BUILDROOT/"tmp"
  # The list of module files (with info) that have been processed.
  MODLIST   = TMP/"modules.txt"
  # The source files that need to be compiled and documentation generated for.
  FILES     = []
  # The folders and files which were produced by a build.
  PRODUCED  = []

  sw, sw_all = StopWatch(), StopWatch()

  # Check out a new working copy.
  BUILDROOT.rm().mkdir() # First remove the whole folder and recreate it.
  if options.src != None:
    # Use the source folder specified by the user.
    src = Path(options.src)
    if not src.exists:
      parser.error("the given SRC path (%s) doesn't exist" % src)
    #if src.ext in ('zip', 'gz', 'bz2'):
      # TODO:
    src.copy(DEST)
  else:
    if not locate_command('git'):
      parser.error("'git' is not in your PATH; specify --src instead")
    if not locate_command('tar'):
      parser.error("program 'tar' is not in your PATH")
    # Use git to checkout a clean copy.
    DEST.mkdir()
    TARFILE = DEST/"dil.tar"
    call_proc("git", "archive", "-o", TARFILE, "HEAD")
    call_proc("tar", "-xf", TARFILE.name, cwd=DEST)
    TARFILE.rm()
    if options.copy_modified:
      modified_files = call_read("git", "ls-files", "-m")[:-1]
      if modified_files != "":
        for f in modified_files.split("\n"):
          Path(f).copy(DEST/f)
  # Create other directories not available in a clean checkout.
  DOC = DEST.DOC
  Paths(DOC.HTMLSRC, DOC.CSS, DOC.IMG, DOC.JS, TMP).mkdirs()

  # Rebuild the path object for kandil. (Images are globbed.)
  DEST.KANDIL = kandil_path(DEST/"kandil")

  print("== Copying files ==")
  copy_files(DEST)

  # Find the source code files.
  FILES = find_dil_source_files(DEST.SRC)

  # Update the version info.
  update_VERSION(DEST.SRC/"dil"/"Version.d", VERSION)
  write_VERSION(VERSION, DEST)

  if options.docs:
    build_dil_if_inexistant(DIL.EXE)

    print("== Generating documentation ==")
    DOC_FILES = DEST.DATA/("macros_dil.ddoc", "dilconf.d") + FILES
    versions = ["DDoc"]
    generate_docs(DIL.EXE, DEST.DOC, MODLIST, DOC_FILES,
                  versions, options=['-v', '-i', '-hl', '--kandil'])

  if options.pdf:
    write_PDF(DEST, DEST.DOC, VERSION, TMP)
  #if options.chm:
    #write_CHM(DEST, DEST.DOC, VERSION, TMP)

  TARGETS = [Targets[n] for n in ("Lin32", "Lin64", "Win32")]

  if not options.no_binaries:
    BINS = build_binaries(TARGETS, COMPILER, VERSION.MAJ, FILES, DEST)
    for bin in BINS:
      (DIL.DATA/"dilconf.d").copy(bin.folder)

  PRODUCED += [(DEST.abspath, sw.stop())]

  # Remove unneeded directories.
  options.docs or DEST.DOC.rm()

  # Build archives.
  assert DEST[-1] != Path.sep
  create_archives(options, DEST.name, DEST.name, DEST.folder)

  if options.deb and not options.no_binaries:
    MTR = get_MAINTAINER(options.deb_mntnr)
    NUM = int(options.deb_num)
    # Make an archive for each architecture.
    SRC = Path(DEST)
    SRC.DATA = DEST.DATA
    SRC.DOC  = DEST.DOC
    LINUX_BINS = [bin for bin in BINS if bin.target.islin]
    for arch in ("i386", "amd64"):
      # Gather the binaries that belong to arch.
      SRC.BINS  = [bin for bin in LINUX_BINS if bin.target.arch == arch]
      sw.start()
      DEB = make_deb_package(SRC, DEST.folder, VERSION, arch, DEST, MTR, NUM)
      PRODUCED += [(DEB.abspath, sw.stop())]

  if not options.no_binaries:
    # Make an arch-independent folder.
    NOARCH = TMP/"dil_noarch"
    DEST.copy(NOARCH)
    (NOARCH/("linux", "windows")).rm()

    # Linux:
    for bits in (32, 64):
      BIN = DEST/"linux"/"bin%d"%bits
      if not BIN.exists: continue
      SRC = (TMP/"dil_"+VERSION).rm() # Clear if necessary.
      NOARCH.copy(SRC)
      BIN.copy(SRC/"bin")
      write_modified_dilconf(SRC/"data"/"dilconf.d", SRC/"bin"/"dilconf.d",
        Path("${BINDIR}")/".."/"data")
      NAME = BUILDROOT.abspath/"dil_%s_linux%s" % (VERSION, bits)
      for ext in (".7z", ".tar.xz"):
        sw.start()
        make_archive(SRC, NAME+ext)
        PRODUCED += [(NAME+ext, sw.stop())]
      SRC.rm()

    # Windows:
    for bits in (32, 64):
      if bits != 32: continue # Only 32bit supported atm.
      BIN = DEST/"windows"/"bin%d"%bits
      if not BIN.exists: continue
      SRC = (TMP/"dil_"+VERSION).rm() # Clear if necessary.
      NOARCH.copy(SRC)
      BIN.copy(SRC/"bin")
      write_modified_dilconf(SRC/"data"/"dilconf.d", SRC/"bin"/"dilconf.d",
        Path("${BINDIR}")/".."/"data")
      NAME = BUILDROOT.abspath/"dil_%s_win%s" % (VERSION, bits)
      for ext in (".7z", ".zip"):
        sw.start()
        make_archive(SRC, NAME+ext)
        PRODUCED += [(NAME+ext, sw.stop())]
      SRC.rm()
    NOARCH.rm()

    # All platforms:
    NAME = BUILDROOT.abspath/"dil_%s_all" % VERSION
    for ext in (".7z", ".zip", ".tar.xz"):
      sw.start()
      make_archive(DEST, NAME+ext)
      PRODUCED += [(NAME+ext, sw.stop())]

  TMP.rm()

  if PRODUCED:
    print("\nProduced files/folders:")
    for x, sec in PRODUCED:
      if Path(x).exists:
        print(x+" (%.2fs)"%sec)
    print()


  print("Finished in %.2fs!" % sw_all.stop())

if __name__ == '__main__':
  main()
