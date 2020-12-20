import asyncdispatch, asyncfutures, sequtils, strutils, json, options
import ../lib/genutils
import ../lib/io/cli, ../lib/io/files, ../lib/io/http, ../lib/io/io, ../lib/io/term
import ../lib/obj/manifest, ../lib/obj/manifestutils, ../lib/obj/mods, ../lib/obj/modutils, ../lib/obj/verutils

type
  InstallStrategy* = enum
    ## Strategy when installing/updating mods.
    ## recommended =  newest version which is compatible with the modpack version.
    ## newest = newest version which is compatible with the minor modpack version.
    recommended, newest

proc searchForMod*(project: ManifestProject, search: string, installed: bool): McMod =
  ## let the user select a mod from a list
  ## list retrieved by searching the mod database for the search string
  var mcMods = parseJson(fetch(searchUrl(search))).modsFromJson
  if installed:
    if project.files.len == 0:
      echoError "No mods installed yet."
      quit(1)
    mcMods = mcMods.filter(proc(m: McMod): bool = project.isInstalled(m.projectId))
    if mcMods.len == 0:
      echoError "No mods found for your search."
      quit(1)
    if mcMods.len == 1:
      return mcMods[0]

  echoRoot "RESULTS".clrGray
  for index, mcMod in mcMods:
    let indexStr = not installed and project.isInstalled(mcMod.projectId) ? ("    ", ("[" & $(index+1) & "]").clrCyan.align(13))
    let installStr = project.isInstalled(mcMod.projectId) ? (" [installed]".clrMagenta, "")
    echo promptPrefix, indexStr, " ", mcMod.name, installStr, " ", mcMod.websiteUrl.clrGray

  var availableIndexes = toSeq(1..mcMods.len)
  if not installed:
    availableIndexes.keepItIf(not project.isInstalled(mcMods[it - 1].projectId))
  let selectedIndex = promptChoice("Select a mod", availableIndexes, "1 - " & $mcMods.len)
  let mcMod = mcMods[selectedIndex - 1]
  return mcMod


proc displayMod(project: ManifestProject, mcMod: McMod, mcModFile: Option[McModFile]): void =
  ## display information about the mod on the command line.
  let installStr = mcModFile.isSome ? (" [installed]".clrMagenta, "")
  echoRoot "SELECTED MOD".clrGray
  echo promptPrefix, mcMod.name, installStr, " ", mcMod.websiteUrl.clrGray
  if mcModFile.isSome:
    let file = mcModFile.get()
    let fileCompabilityMessage = file.getFileCompability(project.mcVersion).getMessage()
    let fileFreshnessMessage = file.getFileFreshness(project.mcVersion, mcMod).getMessage()
    echo promptPrefix.indent(3), fileCompabilityMessage
    echo promptPrefix.indent(3), fileFreshnessMessage
    echo "------------------------------".indent(4).clrGray
  echo promptPrefix.indent(3), "Description: ".clrCyan, mcMod.description
  echo promptPrefix.indent(3), "Downloads: ".clrCyan, ($mcMod.downloads).insertSep(sep='.')

proc displayMod*(project: ManifestProject, mcMod: McMod, mcModFile: McModFile): void = displayMod(project, mcMod, some(mcModFile))
proc displayMod*(project: ManifestProject, mcMod: McMod): void = displayMod(project, mcMod, none(McModFile))

proc getModFileToInstall*(project: ManifestProject, mcMod: McMod, strategy: InstallStrategy): McModFile =
  ## get the correct version of the mcMod to download based on the InstallStrategy & Loader.
  echoDebug "Retrieving mod versions.."
  let modFileContent = waitFor(asyncFetch(modFilesUrl(mcMod.projectId)))
  let allModFiles = modFileContent.parseJson.modFilesFromJson

  echoDebug "Checking ", $project.loader, " compability.."
  var latestFile = none[McModFile]()
  for file in allModFiles:
    let onFabric = project.loader == Loader.fabric and "Fabric".Version in file.gameVersions
    let onForge = project.loader == Loader.forge and not ("Fabric".Version in file.gameVersions and not ("Forge".Version in file.gameVersions))
    let onRecommended = strategy == InstallStrategy.recommended and project.mcVersion in file.gameVersions
    let onNewest = strategy == InstallStrategy.newest and project.mcVersion.minor in file.gameVersions.map(minor)
    if latestFile.isNone or latestFile.get().fileId > file.fileId:
      if onFabric or onForge or mcMod.projectId == 361988:
        if onRecommended or onNewest:
          latestFile = some(file)

  if latestFile.isNone:
    echoError "No compatible version found."
    quit(1)
  
  return latestFile.get()
  