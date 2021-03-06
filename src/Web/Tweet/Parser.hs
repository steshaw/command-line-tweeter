{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Module containing parsers for tweet and response data.
module Web.Tweet.Parser ( parseTweet
                        , getData ) where

import Control.Composition ((.*))
import qualified Data.ByteString as BS
import Text.Megaparsec.Byte
import Text.Megaparsec.Byte.Lexer as L
import Text.Megaparsec
import Web.Tweet.Types
import Data.Monoid
import qualified Data.Map as M
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Control.Monad
import Data.Maybe
import Data.Void

type Parser = Parsec Void String

-- | Parse some number of tweets
parseTweet :: Parser Timeline
parseTweet = many (try getData <|> (const (TweetEntity "" "" "" 0 mempty Nothing 0 0) <$> eof))

-- | Parse a single tweet's: n, text, fave count, retweet count
getData :: Parser TweetEntity
getData = do
    idNum <- read <$> filterStr "id" 
    t <- filterStr "text"
    skipMentions
    n <- filterStr "name"
    screenn' <- filterStr "screen_name"
    --withheldCountries <- (catMaybes . sequence) <$> optional filterList
    let withheldCountries = mempty
    --let toBlock = "DE" `elem` (catMaybes (sequence bannedList))
    isQuote <- filterStr "is_quote_status"
    case isQuote of
        "false" -> do
            rts <- read <$> filterStr "retweet_count"
            faves <- read <$> filterStr "favorite_count"
            pure (TweetEntity t n screenn' idNum withheldCountries Nothing rts faves)
        "true" -> do
            q <- parseQuoted
            rts <- read <$> filterStr "retweet_count"
            faves <- read <$> filterStr "favorite_count"
            pure $ TweetEntity t n screenn' idNum withheldCountries q rts faves
        _ -> error "is_quote_status must have a value of \"true\" or \"false\""

-- | Parse a the quoted tweet
parseQuoted :: Parser (Maybe TweetEntity)
parseQuoted = do
    optional (string ",\"quoted_status_id" >> filterStr "quoted_status_id_str") -- FIXME it's skipping too many? prob is when two are deleted in a row twitter just dives in to RTs
    contents <- optional $ string "\",\"quoted_status"
    case contents of
        (Just _) -> pure <$> getData
        _ -> pure Nothing

-- | Skip a set of square brackets []
skipInsideBrackets :: Parser ()
skipInsideBrackets = void (between (char '[') (char ']') $ many (skipInsideBrackets <|> void (noneOf ("[]" :: String))))

-- | Skip user mentions field to avoid parsing the wrong n
skipMentions :: Parser ()
skipMentions = do
    many $ try $ anyChar >> notFollowedBy (string "\"user_mentions\":")
    string ",\"user_mentions\":"
    skipInsideBrackets

-- | Throw out input until we get to a relevant tag.
filterStr :: String -> Parser String
filterStr str = do
    many $ try $ anyChar >> notFollowedBy (string ("\"" <> str <> "\":"))
    char ','
    filterTag str

{-
filterList :: Parser [String]
filterList = try $ do
    many $ try $ anyChar >> notFollowedBy (string ("\"withheld_in_countries\":"))
    char ','
    filterWithheld


filterWithheld :: Parser [String]
filterWithheld = do
    string "\"withheld_in_countries\":[\""
    codes <- some $ do { char '\"' ; interior <- many (noneOf ("\"]" :: String)) ; char '\"' ; optional (char ',') ; pure interior }
    char ']'
    pure codes
    -}

-- | Parse a field given its tag
filterTag :: String -> Parser String
filterTag str = do
    string $ "\"" <> str <> "\":"
    open <- optional $ char '\"'
    let forbidden = if isJust open then ("\\\"" :: String) else ("\\\"," :: String)
    want <- many $ parseHTMLChar <|> noneOf forbidden <|> specialChar '\"' <|> specialChar '/' <|> newlineChar <|> emojiChar <|> unicodeChar -- TODO modify parsec to make this parallel?
    pure want

-- | Parse a newline
newlineChar :: Parser Char
newlineChar = string "\\n" >> pure '\n'

-- | Parser for unicode; twitter will give us something like "/u320a"
unicodeChar :: Parser Char
unicodeChar = toEnum . fromIntegral . f <$> go
    where go = string "\\u" >> count 4 anyChar
          f = fromHex . filterEmoji . BS.pack . fmap (fromIntegral . fromEnum) 

emojiChar :: Parser Char
emojiChar = go a
    where a = string "\\ud" >> count 3 anyChar
          go = (<*>) =<< (((T.head . decodeUtf16) .* ((<>) . (<> "d") . ("d" <>))) <$>)

decodeUtf16 :: String -> T.Text
decodeUtf16 = TE.decodeUtf16BE . BS.concat . go
    where
        go []             = []
        go (a:b:c:d:rest) = let sym = convert16 [a,b] [c,d] in sym : go rest
        go _ = error "Internal error: decodeUtf16 failed."
        convert16 x y = BS.pack [(read . ("0x"<>)) x, (read . ("0x"<>)) y]

-- | helper function to ignore emoji
filterEmoji :: BS.ByteString -> BS.ByteString
filterEmoji str = if BS.head str == (fromIntegral . fromEnum $ 'd') then "FFFD" else str

-- | Parse HTML chars
parseHTMLChar :: Parser Char
parseHTMLChar = do
    char '&'
    innards <- many $ noneOf (";" :: String)
    char ';'
    pure . (\case 
        (Just a) -> a 
        Nothing -> '?') $ M.lookup innards (M.fromList [("amp",'&'),("gt",'>'),("lt",'<'),("quot",'"'),("euro",'€'),("ndash",'–'),("mdash",'—')])

-- | Parse escaped characters
specialChar :: Char -> Parser Char
specialChar c = string ("\\" <> pure c) >> pure c

-- | Convert a string of four hexadecimal digits to an integer.
fromHex :: BS.ByteString -> Integer
fromHex = fromRight . parseMaybe (L.hexadecimal :: Parsec Void BS.ByteString Integer)
    where fromRight (Just a) = a
          fromRight _        = error "failed to parse hex"
