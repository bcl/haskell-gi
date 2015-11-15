module GI.Cabal
    ( genCabalProject
    , cabalConfig
    , setupHs
    ) where

#if !MIN_VERSION_base(4,8,0)
import Control.Applicative ((<$>), (<*>))
#endif
import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Data.List (intercalate)
import Data.Maybe (fromMaybe)
import Data.Monoid ((<>))
import Data.Version (Version(..),  showVersion)
#if MIN_VERSION_base(4,8,0)
import Data.Version (makeVersion)
#endif
import qualified Data.Map as M
import qualified Data.Text as T
import Data.Text (Text)
import Text.Read

import GI.API (GIRInfo(..))
import GI.Code
import GI.Config (Config(..))
import GI.Overrides (pkgConfigMap, cabalPkgVersion)
import GI.PkgConfig (pkgConfigGetVersion)
import GI.ProjectInfo (homepage, license, authors, maintainers)
import GI.Util (padTo)
import GI.SymbolNaming (ucFirst)

import Paths_haskell_gi (version)

cabalConfig :: Text
cabalConfig = T.unlines ["documentation: False",
                         "optimization: False"]

setupHs :: Text
setupHs = T.unlines ["#!/usr/bin/env runhaskell",
                     "import Distribution.Simple",
                     "main = defaultMain"]

haskellGIAPIVersion :: Int
haskellGIAPIVersion = (head . versionBranch) version

#if !MIN_VERSION_base(4,8,0)
-- Create a version without tags, which we ignore anyway. The
-- versionTags constructor field is deprecated in base 4.8.0.
makeVersion :: [Int] -> Version
makeVersion branch = Version branch []
#endif

haskellGIRevision :: String
haskellGIRevision =
    showVersion $ makeVersion (tail (versionBranch version))

{- |

If the haskell-gi version is of the form x.y and the pkgconfig version
of the package being wrapped is a.b.c, this gives something of the
form x.a.b.y.

This strange seeming-rule is so that the packages that we produce
follow the PVP, assuming that the package being wrapped follows the
usual semantic versioning convention (http://semver.org) that
increases in "a" indicate non-backwards compatible changes, increases
in "b" backwards compatible additions to the API, and increases in "c"
denote API compatible changes (so we do not need to regenerate
bindings for these, at least in principle, so we do not encode them in
the cabal version).

In order to follow the PVP, then everything we need to do in the
haskell-gi side is to increase x everytime the generated API changes
(for a fixed a.b.c version).

In any case, if such "strange" package numbers are undesired, or the
wrapped package does not follow semver, it is possible to add an
explicit cabal-pkg-version override. This needs to be maintained by
hand (including in the list of dependencies of packages depending on
this one), so think carefully before using this override!

-}
giModuleVersion :: Int -> Int -> Text
giModuleVersion major minor = T.pack $
    show haskellGIAPIVersion ++ "." ++ show major ++ "."
             ++ show minor ++ "." ++ haskellGIRevision

-- | Smallest version not backwards compatible with the current
-- version (according to PVP).
nextIncompatibleVersion :: Int -> Text
nextIncompatibleVersion major = T.pack $
    show haskellGIAPIVersion ++ "." ++ show (major+1)

-- | Determine the pkg-config name and installed version (major.minor
-- only) for a given module, or throw an exception if that fails.
tryPkgConfig :: Text -> Text -> [Text] -> Bool
             -> M.Map Text Text
             -> ExcCodeGen (Text, Int, Int)
tryPkgConfig name version packages verbose overridenNames =
    liftIO (pkgConfigGetVersion name version packages verbose overridenNames) >>= \case
           Just (n,v) ->
               case readMajorMinor v of
                 Just (major, minor) -> return (n, major, minor)
                 Nothing -> notImplementedError . T.unpack $
                            "Cannot parse version \""
                            <> v <> "\" for module " <> name
           Nothing -> missingInfoError . T.unpack $
                      "Could not determine the pkg-config name corresponding to \"" <> name <> "\".\n" <>
                      "Try adding an override with the proper package name:\n"
                      <> "pkg-config-name " <> name <> " [matching pkg-config name here]"

-- | Given a string a.b.c..., representing a version number, determine
-- the major and minor versions, i.e. "a" and "b". If successful,
-- return (a,b).
readMajorMinor :: Text -> Maybe (Int, Int)
readMajorMinor version =
    case T.splitOn "." version of
      (a:b:_) -> (,) <$> readMaybe (T.unpack a) <*> readMaybe (T.unpack b)
      _ -> Nothing

-- | Try to generate the cabal project. In case of error return the
-- corresponding error string.
genCabalProject :: GIRInfo -> [GIRInfo] -> String -> CodeGen (Maybe String)
genCabalProject gir deps modulePrefix =
    handleCGExc (return . Just . describeCGError) $ do
      cfg <- config
      let pkMap = pkgConfigMap (overrides cfg)
          name = girNSName gir
          pkgVersion = girNSVersion gir
          packages = girPCPackages gir

      line $ "-- Autogenerated, do not edit."
      line $ padTo 20 "name:" <> "gi-" <> T.unpack (T.toLower name)
      (pcName, major, minor) <- tryPkgConfig name pkgVersion packages (verbose cfg) pkMap
      let cabalVersion = fromMaybe (giModuleVersion major minor)
                                   (cabalPkgVersion $ overrides cfg)
      line $ padTo 20 "version:" ++ T.unpack cabalVersion
      line $ padTo 20 "synopsis:" ++ T.unpack name
               ++ " bindings"
      line $ padTo 20 "description:" ++ "Bindings for " ++ T.unpack name
               ++ ", autogenerated by haskell-gi."
      line $ padTo 20 "homepage:" ++ homepage
      line $ padTo 20 "license:" ++ license
      line $ padTo 20 "license-file:" ++ "LICENSE"
      line $ padTo 20 "author:" ++ authors
      line $ padTo 20 "maintainer:" ++ maintainers
      line $ padTo 20 "category:" ++ "Bindings"
      line $ padTo 20 "build-type:" ++ "Simple"
      line $ padTo 20 "cabal-version:" ++ ">=1.10"
      blank
      line $ "library"
      indent $ do
        line $ padTo 20 "default-language:" ++ "Haskell2010"
        let base = modulePrefix ++ ucFirst (T.unpack name)
        line $ padTo 20 "exposed-modules:" ++
               intercalate ", " [base, base ++ "Attributes", base ++ "Signals"]
        line $ padTo 20 "pkgconfig-depends:" ++ T.unpack pcName ++ " >= "
                 ++ show major ++ "." ++ show minor
        line $ padTo 20 "build-depends: base >= 4.7 && <5,"
        indent $ do
          line $ "haskell-gi-base >= " ++ showVersion version
                 ++ " && < " ++ show (haskellGIAPIVersion + 1) ++ ","
          forM_ deps $ \dep -> do
              let depName = girNSName dep
                  depVersion = girNSVersion dep
                  depPackages = girPCPackages dep
              (_, depMajor, depMinor) <- tryPkgConfig depName depVersion
                                         depPackages (verbose cfg) pkMap
              line . T.unpack $ "gi-" <> T.toLower depName <> " >= "
                       <> giModuleVersion depMajor depMinor
                       <> " && < " <> nextIncompatibleVersion depMajor <> ","
          -- Our usage of these is very basic, no reason to put any
          -- strong upper bounds.
          line "bytestring >= 0.10,"
          line "containers >= 0.5,"
          line "text >= 1.0,"
          line "transformers >= 0.3"

      return Nothing -- successful generation, no error