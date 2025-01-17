import regex, sequtils, strutils, sugar
import ../api/cf
import ../cli/clr
import ../mc/version

type
  Compability* = enum
    ## compability of a mod version with the modpack version
    ## none = will not be compatible
    ## major = mod major version matches modpack major version, probably compatible
    ## full = mod version exactly matches modpack version, fully compatible
    none, major, full

  Freshness* = enum
    ## if an update to the currently installed version is available
    ## old = file is not the latest version for all gameversions
    ## newestForAVersion = file is the latest version for a gameversion
    ## newest = file is the newest version for the current modpack version
    old, newestForAVersion, newest

const
  ## icon for compability
  compabilityIcon = "•"
  ## icon for freshness
  freshnessIcon = "↑"

proc getCompability*(file: CfModFile, modpackVersion: Version): Compability =
  ## get compability of a file
  if modpackVersion in file.gameVersions: return Compability.full
  if modpackVersion.minor in file.gameVersions.proper.map(minor): return Compability.major
  return Compability.none

proc getIcon*(c: Compability): TermOut =
  ## get the color for a compability
  case c:
    of Compability.full: compabilityIcon.greenFg
    of Compability.major: compabilityIcon.yellowFg
    of Compability.none: compabilityIcon.redFg

proc getMessage*(c: Compability): string =
  ## get the message for a certain compability
  case c:
    of Compability.full: "The installed mod is compatible with the modpack's minecraft version."
    of Compability.major: "The installed mod only matches the major version as the modpack. Issues may arise."
    of Compability.none: "The installed mod is incompatible with the modpack's minecraft version."

proc getFreshness*(file: CfModFile, modpackVersion: Version, cfMod: CfMod): Freshness =
  ## get freshness of a file
  let latestFiles = cfMod.gameVersionLatestFiles
  let modpackVersionFiles = latestFiles.filter((x) => x.version == modpackVersion)
  if modpackVersionFiles.len == 1:
    if modpackVersionFiles[0].fileId == file.fileId:
      return Freshness.newest
  if latestFiles.any((x) => x.fileId == file.fileId and x.version.minor == modpackVersion.minor):
    return Freshness.newestForAVersion
  return Freshness.old

proc getIcon*(f: Freshness): TermOut =
  ## get the color for a freshness
  case f:
    of Freshness.newest: freshnessIcon.greenFg
    of Freshness.newestForAVersion: freshnessIcon.yellowFg
    of Freshness.old: freshnessIcon.redFg

proc getMessage*(f: Freshness): string =
  ## get the message for a certain freshness
  case f:
    of Freshness.newest: "No mod updates available."
    of Freshness.newestForAVersion: "Your installed version is newer than the recommended version. Issues may arise."
    of Freshness.old: "There is a newer version of this mod available."

proc isFabricMod*(file: CfModFile): bool =
  ## returns true if `file` is a fabric mod.
  if "Fabric".Version in file.gameVersions:
    return true
  elif file.name.toLower.match(re".*\Wfabric\W.*"):
    return true
  return false

proc isForgeMod*(file: CfModFile): bool =
  ## returns true if `file` is a forge mod.
  if file.name.toLower.match(re".*\Wfabric\W.*"):
    return false
  if not ("Fabric".Version in file.gameVersions and not ("Forge".Version in file.gameVersions)):
    return true
  elif file.name.toLower.match(re".*\Wforge\W.*"):
    return true
  return false