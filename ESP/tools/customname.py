# Description: Custom name for firmware

Import("env")
import subprocess
import sys
import re
import os
import gzip
from colors import *

project = ""
version = ""
commit = ""
branch = ""


def generate_webpage(version):
    project_dir = env.subst("$PROJECT_DIR")
    src = os.path.join(project_dir, "..", "ui_preview.html")
    dst = os.path.join(project_dir, "lib", "src", "network", "api", "baseAPI", "controlWebpage.h")

    try:
        with open(src, "r", encoding="utf-8") as f:
            html = f.read()
    except FileNotFoundError:
        sys.stdout.write(RED)
        print("[webpage]: ui_preview.html not found at %s" % src)
        sys.stdout.write(RESET)
        return

    # Inject version
    html = html.replace("{{FIRMWARE_VERSION}}", "v%s" % version)

    # Remove HTML comments
    html = re.sub(r"<!--.*?-->", "", html, flags=re.DOTALL)
    # Remove CSS block comments
    html = re.sub(r"/\*.*?\*/", "", html, flags=re.DOTALL)

    # Strip each line; skip standalone JS line comments
    lines = []
    for line in html.split("\n"):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        lines.append(stripped)

    html = "".join(lines)
    # Collapse multiple spaces left by comment removal
    html = re.sub(r" {2,}", " ", html)

    content = (
        "#ifndef CONTROL_WEBPAGE_H\n"
        "#define CONTROL_WEBPAGE_H\n\n"
        "#include <Arduino.h>\n\n"
        'const char CONTROL_HTML[] PROGMEM = R"rawliteral(\n'
        + html + "\n"
        ')rawliteral";\n\n'
        "#endif\n"
    )

    with open(dst, "w", encoding="utf-8") as f:
        f.write(content)

    sys.stdout.write(GREEN)
    print("[webpage]: Generated controlWebpage.h  <- v%s" % version)
    sys.stdout.write(RESET)


def generate_elegant_webpage():
    project_dir = env.subst("$PROJECT_DIR")
    src = os.path.join(project_dir, "..", "elegant_ota_with_github.html")
    dst = os.path.join(
        project_dir, "lib", "src", "network", "api", "baseAPI", "elegantWebpage.h"
    )

    try:
        with open(src, "rb") as f:
            html = f.read()
    except FileNotFoundError:
        sys.stdout.write(RED)
        print("[webpage]: elegant_ota_with_github.html not found at %s" % src)
        sys.stdout.write(RESET)
        return

    # mtime=0 keeps the generated header identical when the HTML has not changed.
    compressed = gzip.compress(html, compresslevel=9, mtime=0)
    values = [str(value) for value in compressed]
    rows = [",".join(values[i : i + 30]) for i in range(0, len(values), 30)]
    byte_array = ",\n".join(rows)

    content = (
        "#ifndef ElegantOTAWebpage_h\n"
        "#define ElegantOTAWebpage_h\n\n"
        "#include <Arduino.h>\n\n"
        "const uint32_t ELEGANT_HTML_SIZE = %d;\n"
        "const uint8_t ELEGANT_HTML[] PROGMEM = {\n%s\n};\n\n"
        "#endif\n"
    ) % (len(compressed), byte_array)

    with open(dst, "w", encoding="utf-8") as f:
        f.write(content)

    sys.stdout.write(GREEN)
    print("[webpage]: Generated elegantWebpage.h (%d gzip bytes)" % len(compressed))
    sys.stdout.write(RESET)


def onError():
    print("Please install Git for Windows and add it to your PATH")
    print(
        "Continuing with default values for PIO_SRC_NAM, PIO_SRC_TAG, PIO_SRC_REV, PIO_SRC_BRH"
    )
    sys.stdout.write(RESET)

    project = "PIO"
    version = "0.0.0"
    commit = "0000000"
    branch = "main"

    customName(project, version, commit, branch)


def handleGit():
    try:
        checkgit = "git rev-parse --is-inside-work-tree"

        if subprocess.check_output(checkgit, shell=True).decode().strip() != "true":
            sys.stdout.write(RED)
            onError()

        sys.stdout.write(GREEN)
        print("Git is installed and we are in a Git repository,  continuing...")
        sys.stdout.write(RESET)

        # Get Git project name
        projcmd = "git rev-parse --show-toplevel"
        project = subprocess.check_output(projcmd, shell=True).decode().strip()
        project = project.split("/")
        project = project[len(project) - 1]

        # Get 0.0.0 version from latest Git tag
        tagcmd = "git describe --tags --always --abbrev=0"
        version = subprocess.check_output(tagcmd, shell=True).decode().strip()

        # Get latest commit short from Git
        revcmd = "git log --pretty=format:'%h' -n 1"
        commit = subprocess.check_output(revcmd, shell=True).decode().strip()

        # Get branch name from Git
        branchcmd = "git rev-parse --abbrev-ref HEAD"
        branch = subprocess.check_output(branchcmd, shell=True).decode().strip()

        print("Project: %s" % project)
        print("Version: %s" % version)
        print("Commit: %s" % commit)
        print("Branch: %s" % branch)

        # Make all available for use in the macros
        customName(project, version, commit, branch)

        sys.stdout.write(GREEN)
        print("Git information has been added to the build flags")
        # print(env.Dump())
        sys.stdout.write(RESET)

    except subprocess.CalledProcessError as e:
        sys.stdout.write(RED)
        print("Error: %s" % e)
        onError()


def customName(project, version, commit, branch):

    my_flags = env.ParseFlags(env["BUILD_FLAGS"])
    defines = dict()

    # add the git information to the build flags
    my_flags.get("CPPDEFINES").append(("PIO_SRC_NAM", project))
    my_flags.get("CPPDEFINES").append(("PIO_SRC_TAG", version))
    my_flags.get("CPPDEFINES").append(("PIO_SRC_REV", commit))
    my_flags.get("CPPDEFINES").append(("PIO_SRC_BRH", branch))

    for x in my_flags.get("CPPDEFINES"):
        if type(x) is tuple:
            (k, v) = x
            defines[k] = v
            # print("Type Tuple: %s" % x)
        elif type(x) is list:
            k = x[0]
            v = x[1]
            defines[k] = v
            # print("Type List: %s" % x)
        else:
            defines[x] = ""  # empty value
            # print("Warning: unknown type for %s" % x)

    # print("Project: %s" % defines)
    # strip quotes needed for shell escaping
    s = lambda x: x.replace('"', "")
    s = lambda x: x.replace("'", "")

    """ env.Replace(
        PROGNAME="%s-%s-%s-%s-%s"
        % (
            s(defines.get("PIO_SRC_NAM")),
            s(defines.get("PIO_SRC_TAG")),
            str(env["PIOENV"]),
            s(defines.get("PIO_SRC_REV")),
            s(defines.get("PIO_SRC_BRH")),
        )
    ) """

    firm_version = env.GetProjectOption("custom_firmware_version")

    # strip quotes needed for shell escaping in the firmware version

    if firm_version is None:
        firm_version = "0.0.0"
    else:
        firm_version = firm_version.replace('"', "")
        firm_version = firm_version.replace("'", "")

    env.Replace(
        PROGNAME="%s-v%s-%s"
        % (
            str(env["PIOENV"]),
            firm_version,
            s(defines.get("PIO_SRC_BRH")),
        )
    )

    # detect if there is a forward slash in the PROGNAME and replace it with an underscore
    if "/" in env["PROGNAME"]:
        env.Replace(PROGNAME="%s" % (env["PROGNAME"].replace("/", "-")))

    # create a file with the name of the firmware
    env.Execute(
        "echo %s > %s" % (env["PROGNAME"], env.subst("./tools/firmware_name.txt"))
    )

    # replace the VERSION macro with the version from Git
    env.Replace(VERSION="%s" % (s(defines.get("PIO_SRC_TAG"))))

    # Generate controlWebpage.h from ui_preview.html with the current version
    generate_webpage(firm_version)
    # Generate the gzip-compressed OTA webpage embedded by /update
    generate_elegant_webpage()


try:
    flags = env["BUILD_FLAGS"]
    my_flags = env.ParseFlags(flags)

    # detect if the PIOENV has QIO flash mode
    flash_mode = env["BOARD_FLASH_MODE"]
    # detect the chip type
    chip_type = env["BOARD_MCU"]

    print("Flash Mode: %s" % flash_mode)
    print("Chip Type: %s" % chip_type)

    # Dump global construction environment (for debug purpose)
    # write env.Dump() to a file
    with open("./tools/env_dump.txt", "w") as f:
       f.write(env.Dump())

    handleGit()
except ValueError as ex:
    # look for apostrophes and warn the user
    sys.stdout.write(RED)
    print(
        "[Warning]: Apostrophes are not allowed in the build flags. Please remove them from the \033[;1m\033[1;36m`user-config.ini` \033[1;31mfile and try again."
    )
    raise Exception(
        "Could not parse BUILD_FLAGS - Possible apostrophe used in user configuration",
        ex,
    )
