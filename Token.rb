
# Generates tokens for downloading APKs

class Token

  # How long the download token is
  TOKEN_LENGTH = 6

  # this character set is used to create a token that will be used to download
  # an APK. We assumed that the token will be entered by a human using a mobile
  # devices' keyboard. To expedite entry, only lower case it used and no numbers.
  # To eliminate human error the chracters below omit
  # omitted  | looks like
  #  l           I, 1
  #  f           t
  #  q           g
  #  j           i
  CHARACTER_SET= "abcdeghikmnoprstuwxyz".split("")

  def self.make
    (1..Token::TOKEN_LENGTH).map{|x| Token::CHARACTER_SET[rand(Token::CHARACTER_SET.length)]}.join()
  end

end