-- | Support for enums and flags.
module Data.GI.CodeGen.EnumFlags
    ( genEnum
    , genFlags
    ) where

import Control.Monad (when, forM_)
import Data.Monoid ((<>))
import Data.Text (Text)

import Foreign.C (CUInt)
import Foreign.Storable (sizeOf)

import Data.GI.CodeGen.API
import Data.GI.CodeGen.Code
import Data.GI.CodeGen.Haddock (deprecatedPragma, writeDocumentation,
                                writeHaddock, RelativeDocPosition(..))
import Data.GI.CodeGen.SymbolNaming (upperName)
import Data.GI.CodeGen.Util (tshow)

genEnumOrFlags :: Name -> Enumeration -> ExcCodeGen ()
genEnumOrFlags n@(Name ns name) e = do
  -- Conversion functions expect enums and flags to map to CUInt,
  -- which we assume to be of 32 bits. Fail early, instead of giving
  -- strange errors at runtime.
  when (sizeOf (0 :: CUInt) /= 4) $
       notImplementedError $ "Unsupported CUInt size: " <> tshow (sizeOf (0 :: CUInt))
  when (enumStorageBytes e /= 4) $
       notImplementedError $ "Storage of size /= 4 not supported : " <> tshow (enumStorageBytes e)

  let name' = upperName n
      members' = flip map (enumMembers e) $ \member ->
        let n = upperName $ Name ns (name <> "_" <> enumMemberName member)
        in (n, member)

  deprecatedPragma name' (enumDeprecated e)

  group $ do
    exportDecl (name' <> "(..)")
    hsBoot . line $ "data " <> name'
    writeDocumentation DocBeforeSymbol (enumDocumentation e)
    line $ "data " <> name' <> " = "
    indent $
      case members' of
        ((fieldName, firstMember):fs) -> do
          line $ "  " <> fieldName
          writeDocumentation DocAfterSymbol (enumMemberDoc firstMember)
          forM_ fs $ \(n, member) -> do
            line $ "| " <> n
            writeDocumentation DocAfterSymbol (enumMemberDoc member)
          line $ "| Another" <> name' <> " Int"
          writeHaddock DocAfterSymbol "Catch-all for unknown values"
          line "deriving (Show, Eq)"
        _ -> return ()

  group $ do
    bline $ "instance P.Enum " <> name' <> " where"
    indent $ do
            forM_ members' $ \(n, m) ->
                line $ "fromEnum " <> n <> " = " <> tshow (enumMemberValue m)
            line $ "fromEnum (Another" <> name' <> " k) = k"
    blank
    indent $ do
            forM_ members' $ \(n, m) ->
                line $ "toEnum " <> tshow (enumMemberValue m) <> " = " <> n
            line $ "toEnum k = Another" <> name' <> " k"

  group $ do
    line $ "instance P.Ord " <> name' <> " where"
    indent $ line "compare a b = P.compare (P.fromEnum a) (P.fromEnum b)"

  maybe (return ()) (genErrorDomain name') (enumErrorDomain e)

genBoxedEnum :: Name -> Text -> CodeGen ()
genBoxedEnum n typeInit = do
  let name' = upperName n

  group $ do
    line $ "foreign import ccall \"" <> typeInit <> "\" c_" <>
            typeInit <> " :: "
    indent $ line "IO GType"
  group $ do
       bline $ "instance BoxedEnum " <> name' <> " where"
       indent $ line $ "boxedEnumType _ = c_" <> typeInit

genEnum :: Name -> Enumeration -> CodeGen ()
genEnum n@(Name _ name) enum = do
  line $ "-- Enum " <> name

  handleCGExc (\e -> line $ "-- XXX Could not generate: " <> describeCGError e)
              (do genEnumOrFlags n enum
                  case enumTypeInit enum of
                    Nothing -> return ()
                    Just ti -> genBoxedEnum n ti)

genBoxedFlags :: Name -> Text -> CodeGen ()
genBoxedFlags n typeInit = do
  let name' = upperName n

  group $ do
    line $ "foreign import ccall \"" <> typeInit <> "\" c_" <>
            typeInit <> " :: "
    indent $ line "IO GType"
  group $ do
       bline $ "instance BoxedFlags " <> name' <> " where"
       indent $ line $ "boxedFlagsType _ = c_" <> typeInit

-- | Very similar to enums, but we also declare ourselves as members of
-- the IsGFlag typeclass.
genFlags :: Name -> Flags -> CodeGen ()
genFlags n@(Name _ name) (Flags enum) = do
  line $ "-- Flags " <> name

  handleCGExc (\e -> line $ "-- XXX Could not generate: " <> describeCGError e)
              (do
                genEnumOrFlags n enum

                case enumTypeInit enum of
                  Nothing -> return ()
                  Just ti -> genBoxedFlags n ti

                let name' = upperName n
                group $ bline $ "instance IsGFlag " <> name')

-- | Support for enums encapsulating error codes.
genErrorDomain :: Text -> Text -> CodeGen ()
genErrorDomain name' domain = do
  group $ do
    line $ "instance GErrorClass " <> name' <> " where"
    indent $ line $
               "gerrorClassDomain _ = \"" <> domain <> "\""
  -- Generate type specific error handling (saves a bit of typing, and
  -- it's clearer to read).
  group $ do
    let catcher = "catch" <> name'
    line $ catcher <> " ::"
    indent $ do
            line   "IO a ->"
            line $ "(" <> name' <> " -> GErrorMessage -> IO a) ->"
            line   "IO a"
    line $ catcher <> " = catchGErrorJustDomain"
  group $ do
    let handler = "handle" <> name'
    line $ handler <> " ::"
    indent $ do
            line $ "(" <> name' <> " -> GErrorMessage -> IO a) ->"
            line   "IO a ->"
            line   "IO a"
    line $ handler <> " = handleGErrorJustDomain"
  exportToplevel ("catch" <> name')
  exportToplevel ("handle" <> name')
