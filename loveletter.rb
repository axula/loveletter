require 'cinch'

$card_lookup = Hash.new
$card_lookup["guard"] = { "value" => 1, "qty" => 5, "brief" => "Guess a player's hand", "text" => "When you discard the Guard, choose a player and name a card (other than Guard). If that player has that card, that player is knocked out of the round. If all other players still in the round are protected by the Handmaid, this card does nothing." }
$card_lookup["priest"] = { "value" => 2, "qty" => 2, "brief" => "Look at a hand", "text" => "When you discard the Priest, you can look at one other player's hand. Do not reveal the hand to all players." }
$card_lookup["baron"] = { "value" => 3, "qty" => 2, "brief" => "Compare hands; lower hand is out", "text" => "When discarded, choose one other player still in the round. You and that player secretly compare your hands. The player with the lower rank is knocked out of the round. In case of a tie, nothing happens. If all other players still in the round are protected by the Handmaid, this card does nothing." }
$card_lookup["handmaid"] = { "value" => 4, "qty" => 2, "brief" => "Protection until your next turn", "text" => "When you discard the Handmaid, you are immune to the effects of other players' cards until the start of your next turn. If all players other than the player whose turn it is are protected by the Handmaid, the player must choose him- or herself if possible." }
$card_lookup["prince"] = { "value" => 5, "qty" => 2, "brief" => "One player discards his or her hand", "text" => "When you discard the Prince, choose one player still in the round (including yourself). That player discards his or her hand (do not apply its effect) and draws a new card. If the deck is empty, that player draws the card that was removed at the start of the round. If all other players are protected by the Handmaid, you must choose yourself." }
$card_lookup["king"] = { "value" => 6, "qty" => 1, "brief" => "Trade hands", "text" => "When you discard the King, trade the card in your hand with the card held by another player of your choice. You cannot trade with a player who is out of the round, nor with someone protected by the Handmaid. If all other players still in the round are protected by the Handmaid, this card does nothing." }
$card_lookup["countess"] = { "value" => 7, "qty" => 1, "brief" =>"Discard if caught with a Prince or the King", "text" => "Unlike other cards, which take effect when discarded, the text on the Countess applies while she is in your hand. If you ever have the Countess and either the King or Prince in your hand, you must discard the Countess. You do not have to reveal the other card in your hand. You may volunarily discard the Countess even if you don't also have the King or Prince." }
$card_lookup["princess"] = { "value" => 8, "qty" => 1, "brief" => "Lose if discarded", "text" => "If you discard the Princess - no matter how or why - she has tossed your letter into the fire. You are knocked out of the round." }

$CARDS = ['princess', 'countess', 'king', 'prince', 'prince', 
    'handmaid', 'handmaid', 'baron', 'baron', 'priest', 
    'priest', 'guard', 'guard', 'guard', 'guard', 'guard']

$join_list = Array.new
$game_start = false
$game_channel = ""
$game_round = 0
$game_turn = 0
$players = Array.new
$gametable = Hash.new
$deck = Array.new
$discard = ""
$twopldiscards = Array.new
$winningTokens = 0

class LoveLetter
    include Cinch::Plugin
    
    set :prefix, /^<3 /
    
    def startRound()
        $deck = $CARDS.shuffle
        # discard one card randomly face down
        $discard = $deck.shift
        if $players.length == 2
            $twopldiscards = $deck.shift(3)
            Channel($game_channel).send "These three cards have been discarded: #{$twopldiscards.join(", ")}."
        end
        $gametable.each do |player, data|
            $gametable[player]["hand"] = Array.new
            $gametable[player]["hand"].push($deck.shift)
            User(player).send "Your hand: #{data["hand"].join(", ")}"
        end
    end

    def playValidate(current_player, card_num, player_num, guess)
        card_num = card_num.to_i
        if card_num < 0 || card_num > 1
            User(current_player).send "Please specify your card choice with 0 or 1."
            return false
        end
        card = $gametable[current_player]["hand"][card_num]
        if ['guard', 'priest', 'baron', 'prince', 'king'].include?(card) && !player_num
			# If the card should target someone, but doesn't, makes sure it's because player's only valid option is to discard
            if validTargetsRemaining($gametable[current_player]["hand"][card_num] )
                User(current_player).send "#{card} requires you to target another player by numerical id. You cannot discard a #{$gametable[current_player]["hand"][card_num]} unless there are no valid targets remaining. Please choose your other card, or choose a valid target. #{validTargets()}."
                return false
            end
        end
        if card == "guard" && !guess
            User(current_player).send "To play a guard, please specify which of the following you guess the target has in their hand: guard, priest, baron, handmaid, prince, king, countess, or princess."
            return false
        end
        if player_num
            player_num = player_num.to_i
            remainingPlayers = playersRemaining()
            # check to see if it refers to a valid num
            if player_num > $players.length - 1 || player_num < 0
                User(current_player).send "That player id is not valid."
                return false
            end
            # Check to see if that player is still in the round
            unless remainingPlayers.include? $players[player_num]
                User(current_player).send "Please target a player who is still in the round."
                return false
            end
            if $gametable[$players[player_num]]["discards"] && $gametable[$players[player_num]]["discards"].last == "handmaid" && current_player != $players[player_num]
                User(current_player).send "You cannot target #{$players[player_num]}, since they are protected by a handmaid."
                return false
            end
            # If the player targets himself with a card that does not allow that
            if current_player == $players[player_num] && ["guard", "priest", "baron", "king"].include?( $gametable[current_player]["hand"][card_num])
                User(current_player).send "You cannot target yourself with a #{$gametable[current_player]["hand"][card_num]}. Please target someone else."
                return false
            end
        end
        if guess
            guess.downcase!
            if guess == "guard"
                User(current_player).send "You cannot target a guard with a guard. Please choose a valid guess."
                return false
            elsif not $CARDS.include? guess
                User(current_player).send "Please check your spelling and specify one of the following: priest, baron, handmaid, prince, king, countess, or princess."
                return false
            end
        end
        return true
    end

    def cardScore(card)
        score = $card_lookup[card]["value"]
        return score
    end

    def cardText(card)
        text = $card_lookup[card]["text"]
        return text
    end

    def validTargets()
        result = Array.new
        playersRemaining.each do |p|
            if $gametable[p]["discards"].any? && $gametable[p]["discards"].last == "handmaid"
                result.push( "immune: #{p} (handmaid)" )
            else
                result.push( "#{$players.index(p)}: #{p}" )
            end
        end
        return "#{result.join(", ")}"
    end

    def validTargetsRemaining(card)
        roundPlayers = Array.new
        playersRemaining.each do |p|
            unless !$gametable[p]["discards"].empty? && $gametable[p]["discards"].last == "handmaid"
                if p == $players[$game_turn] && card == "prince"
                    roundPlayers.push(p)
                end
            end
        end
        return !roundPlayers.empty?
    end
    
    def playersRemaining()
        result = Array.new
        $gametable.each do |name, data|
            if data["hand"].length > 0
                result.push(name)
            end
        end
        return result
    end

    def resetGame()
        $game_start = false
        $game_round = 0
        $game_turn = 0
        $players = Array.new
        $gametable = Hash.new
        $deck = Array.new
        $discard = ""
        $twopldiscards = Array.new
        $winningTokens = 0
    end

    match(/help/, method: :helper)
    def helper(m)
        user = m.user.nick
        if game_start && $players.include?(user)
            User(user).send "Check your hand: '<3 hand'"
            User(user).send "Card quick reference: '<3 reference'"
            User(user).send "Get the description of a specific card type: '<3 card [name of card]'"
            User(user).send "Get the syntax to play a specific card: '<3 syntax [name of card]'"
            User(user).send "See player scores: '<3 scores'"
            User(user).send "Check discards for the current round: '<3 discards'"
            User(user).send "Check how many cards remain in the deck: '<3 deck'"
        elsif game_start # And requesting user is not currently in the game
            User(user).send "Join the queue for the next game: '<3 join'"
            User(user).send "Leave queue: '<3 unjoin'"
            User(user).send "See the status of the current game: '<3 status'"
        else
            User(user).send "Join the queue: '<3 join'"
            User(user).send "Leave queue: '<3 unjoin'"
            User(user).send "Start a game: '<3 start game'"
            User(user).send "See the status of a game: '<3 status'"
        end
    end

	match(/game status/, method: :status)
    def status(l)
		if $game_start
            player_list = Array.new
            $gametable.each do |name, data|
                if data["hand"].empty?
                    player_list.push( "#{name} (out of round): #{data["tokens"]} tokens" )
                elsif data["discards"].last == "handmaid"
                    player_list.push( "#{name} (handmaid): #{data["tokens"]} tokens" )
                else
                    player_list.push( "#{name}: #{data["tokens"]} tokens" )
                end
            end
            l.reply "Round #{game_round} (#{$players[game_turn]}'s turn)"
            l.reply "Players: #{player_list.join(", ")}"
            l.reply "Queue for next game: #{$join_list.join(", ")}"
		else
			if $join_list.empty?
				l.reply "No game is in progress. No one is waiting to play."
			elsif $join_list.length > 1
				l.reply "No game is in progress. The following people are waiting to play: #{$join_list.join(", ")}."
			else
				l.reply "No game is in progress. #{$join_list.first.capitalize} is waiting to play."
			end
		end
    end

	# Allows players to add their username to a join list that is referenced at the start of a game.
	match(/join/, method: :join)
    def join(j)
		if $join_list.include?(j.user.nick)
			j.reply "You have already joined the next game."
		else
			$join_list.push(j.user.nick)
            User(j.user.nick).send "You have joined the queue."
		end
		# if a list of elements, join with commas
	    j.reply "Waiting to play: #{$join_list.join(", ")}"
	end

	# Allows players to leave the join list
    match(/unjoin/, method: :unjoin)
    def unjoin(j)
		if $join_list.include?(j.user.nick)
			$join_list.delete(j.user.nick)
			Channel($game_channel).send "#{j.user.nick} has left the queue."
		else
			j.reply "You are not currently waiting to join the next game."
		end
		if $join_list.empty?
			Channel($game_channel).send "No one is waiting to play Love Letter."
        else
			Channel($game_channel).send "Waiting to play: #{$join_list.join(", ")}"
		end
	end

	# Starts the game and sets up the deck
    match(/start game/, method: :start)
    def start(s)
        if $game_start
            s.reply "A game is already in progress."
        elsif $join_list.include?(s.user.nick)
            if $join_list.length < 2
                s.reply "You can't play by yourself."
            else
                $game_channel = s.channel
                $deck = $CARDS.shuffle
                # discard one card randomly face down
                $discard = $deck.shift
                $game_start = true
                $game_round = 1
                $game_turn = 0
                # set players
                if $join_list.length < 5
                    $players = $join_list
                    $join_list = Array.new
                else
                    $players = $join_list[0..3]
                    $join_list = $join_list[4..-1]
                end
                # Randomize the starting turn order
                $players = $players.shuffle
                # Sets the win condition
                if $players.length == 2
                    $winningTokens = 7
                elsif $players.length == 3
                    $winningTokens = 5
                else # 5 players
                    $winningTokens = 4
                end
                # Set up the info representing the game table
                $gametable = Hash.new
                $players.each {|p|
                    $gametable[p] = { "tokens" => 0, "hand" => Array.new, 
                        "discards" => Array.new }
                }
                # Announce the start of the game
                Channel($game_channel).send "A new game has started! The first player to receive #{$winningTokens} tokens wins the Princess's heart."
                Channel($game_channel).send "Turn order: #{$players.join(", ")}"
                # Deal one card to all players
                $gametable.each {|name, x|
                    x["hand"].push($deck.shift)
                    User(name).send "Your hand: #{x["hand"].join(", ")}"
                }
                current_player = $players[0]
                if $players.length == 2
                    $twopldiscards = $deck.shift(3)
                    Channel($game_channel).send "These three cards have been discarded: #{$twopldiscards.join(", ")}."
                end
                Channel($game_channel).send "Current turn: #{current_player}"
                $gametable[current_player]["hand"].push($deck.shift)
                User(current_player).send "Your current cards are 0:#{$gametable[current_player]['hand'][0]} and 1:#{$gametable[current_player]['hand'][1]}. Remaining players are: #{validTargets()}. Please choose one card to play ('<3 play [id of card] [optional parameters]') Message the bot '<3 syntax [card name]' for the specific parameters of your card. Message the bot '<3 reference' for a quick look at the effects of each card type."
            end
        else
            s.reply "You must be in the game queue to start a new game."
        end
    end

    # Allows one of the current players to abort an in progress game
    match(/abort/, method: :abortgame)
    def abortgame(m)
        if $game_start
            if $players.include? m.user.nick
                Channel($game_channel).send "#{m.user.nick} has aborted the current game."
                finalScores = Hash.new
                $gametable.each do |name, data|
                    finalScores[name] = data["tokens"]
                end
                finalScores.sort_by {|k,v| v}.to_h
                scores = Array.new
                finalScores.each do |name, tokens|
                    scores.push( "#{name}: #{tokens} tokens" )
                end
                Channel($game_channel).send "Final scores - #{scores.join(", ")}"
                resetGame()
            else
                m.reply "You cannot abort a game of Love Letter unless you are an active player."
            end
        else
            m.reply "There is no game of Love Letter currently in progress."
        end
    end

    # Returns the current totals for tokens of affection
    match(/scores/, method: :scores)
    def scores(s)
        if $game_start
            score_reply = Array.new
            $gametable.each {|name, data|
                score_reply.push( "#{name}: #{data["tokens"]}" )
            }
            s.reply "Current scores for Love Letter - #{score_reply.join(", ")}"
        end
    end

    # Displays the cards that have been discarded so far in the round
    match(/discards/, method: :alldiscards)
    def alldiscards(m)
        playerDiscards = Array.new
        if $players.length == 2
            playerDiscards.push( "#{$twopldiscards.join(", ")}, " )
        end
        $gametable.each do |name, data|
            if data["discards"].empty?
                playerDiscards.push( "#{name}: none" )
            else
                playerDiscards.push( "#{name}: #{data["discards"].join(", ")}" )
            end
        end
        m.reply "Currently discarded cards:"
        m.reply "#{playerDiscards.join(", ")}"
    end

    # Returns the number of cards remaining in the deck
    match(/deck/, method: :checkdeck)
    def checkdeck(m)
        if $deck.length == 0
            m.reply "There are no cards remaining in the deck. This is the last turn of the round."
        else
            m.reply "There are #{$deck.length} cards left in the deck."
        end
    end

    # Returns your current hand
    match(/hand/, method: :hand)
    def hand(h)
        if $game_start and $players.include?(h.user.nick)
            User(h.user.nick).send "Your current hand: #{$gametable[h.user.nick]["hand"].join(", ")}"
        end
    end

    # Prints a list of cards, including their value, effect, and max quantity
    match(/reference/, method: :reference)
    def reference(m)
        cardDetails = Array.new
        $card_lookup.each do |name, data|
            cardDetails.push( "#{data["value"]} #{name} (#{data["qty"]}): #{data["brief"]}" )
        end
        User(m.user.nick).send "List of Cards:\n#{cardDetails.join("\n")}"
    end

    # Gets the value, full text of effect, and max quantity for a specific card
    match(/card *(\w+)?$/, method: :carddetails)
    def carddetails(m, card)
        card.downcase!
        if $card_lookup.key?(card)
            data = $card_lookup[card]
            User(m.user.nick).send "#{data["value"]} #{card} (#{data["qty"]}):\n#{data["text"]}"
        else
            User(m.user.nick).send( "Please type the name of one of the following types of cards: guard, priest, baron, handmaid, prince, king, countess, or princess. Check your spelling.")
        end
    end

    # Returns the proper syntax to play the given card
    match(/syntax *(\w+)?$/, method: :syntax)
    def syntax(s, card)
        card.downcase!
        case card
            when "guard"
                User(s.user.nick).send "Type: '<3 play [id of card] [id of target player] [guess what card they have]', ex. '<3 play 0 3 baron'"
            when "priest"
                User(s.user.nick).send "Type: '<3 play [id of card] [id of target player]', ex. '<3 play 1 2'"
            when "baron"
                User(s.user.nick).send "Type: '<3 play [id of card] [id of target player]', ex. '<3 play 0, 1'"
            when "handmaid"
                User(s.user.nick).send "Type: '<3 play [id of card]', ex. '<3 play 1'"
            when "prince"
                User(s.user.nick).send "Type: '<3 play [id of card] [id of player]', ex. '<3 play 0 0'"
            when "king"
                User(s.user.nick).send "Type: '<3 play [id of card] [id of player]', ex. '<3 play 1 0'"
            when "countess"
                User(s.user.nick).send "Type: '<3 play [id of card]', ex. '<3 play 0'"
            when "princess"
                User(s.user.nick).send "Type: '<3 play [id of card]', ex. '<3 play 1'"
            else
                User(s.user.nick).send "Please type the name of one of the following types of cards: guard, priest, baron, handmaid, prince, king, countess, or princess. Check your spelling."
        end
    end

    match(/play (\d+) *(\d+)? *(\w+)?$/, method: :love_play)
    def love_play(m, card_num, player_num, guess)
        if m.user.nick == $players[$game_turn] && playValidate(m.user.nick, card_num, player_num, guess)
            card_num = card_num.to_i
            player_num = player_num.to_i
            player = $players[$game_turn]
            if player_num
                target = $players[player_num]
            end
            cardType = $gametable[player]["hand"][card_num]
            $gametable[player]["discards"].push( $gametable[player]["hand"][card_num] )
            $gametable[player]["hand"].delete_at(card_num)
            case cardType
                when "guard"
                    if !guess
                        Channel($game_channel).send "#{player} discards a guard with no effect."
                    elsif $gametable[target]["hand"].include?(guess)
                        Channel($game_channel).send "#{player} played a guard on #{target}, with a guess of #{guess}. #{target} discards a #{guess}, and has been eliminated for the round."
                        $gametable[target]["discards"].push($gametable[target]["hand"].shift)
                    else
                        Channel($game_channel).send "#{player} played a guard on #{target}, with a guess of #{guess}. #{target} does not have a #{guess}."
                    end
                when "priest"
                    if !player_num
                        Channel($game_channel).send "#{player} discards a priest with no effect."
                    else
                        Channel($game_channel).send "#{player} played a priest on #{target}, and peeks at their hand."
                        User(player).send "#{target}'s hand: #{$gametable[target]["hand"][0]}"
                    end
                when "baron"
                    if !player_num
                        Channel($game_channel).send "#{player} discards a baron with no effect."
                    elsif cardScore($gametable[player]["hand"].first) > cardScore($gametable[target]["hand"].first)
                        Channel($game_channel).send "#{player} played a baron on #{target}, and compared hands in secret. #{target} discards a #{$gametable[target]["hand"].first} and is eliminated for the round."
                        User(target).send "#{player} has a #{$gametable[player]["hand"].first}."
                        $gametable[target]["discards"].push($gametable[target]["hand"].shift)
                    elsif cardScore($gametable[player]["hand"].first) < cardScore($gametable[target]["hand"].first)
                        Channel($game_channel).send "#{player} played a baron on #{target}, and compared hands in secret. #{player} discards a #{$gametable[player]["hand"].first} and is eliminated for the round."
                        User(player).send "#{target} has a #{$gametable[target]["hand"].first}."
                        $gametable[player]["discards"].push($gametable[player]["hand"].shift)
                    else # players must have identical cards
                        Channel($game_channel).send "#{player} played a baron on #{target}, and compared hands in secret. Nothing happens."
                        User(player).send "#{target} has a #{$gametable[target]["hand"].first}."
                        User(target).send "#{player} has a #{$gametable[player]["hand"].first}."
                    end
                when "handmaid"
                    Channel($game_channel).send "#{player} played a handmaid, and cannot be targeted by other player's cards until the beginning of his or her next turn."
                when "prince"
                    if !player_num
                        Channel($game_channel).send "#{player} discards a prince with no effect."
                    elsif $gametable[target]["hand"].include?("princess")
                        Channel($game_channel).send "#{player} played a prince. #{target} discards the princess and is eliminated for the round."
                        $gametable[target]["discards"].push($gametable[target]["hand"].shift)
                    else
                        Channel($game_channel).send "#{player} played a prince. #{target} discards a #{$gametable[target]["hand"].first} and draws a new card."
                        $gametable[target]["discards"].push($gametable[target]["hand"].shift)
                        $gametable[target]["hand"].push($deck.shift)
                        User(target).send "Your hand: #{$gametable[target]["hand"].first}"
                    end
                when "king"
                    if !player_num
                        Channel($game_channel).send "#{player} discards the king with no effect."
                    else
                        Channel($game_channel).send "#{player} played the king, and trades hands with #{target}."
                        old_card = $gametable[player]["hand"].shift
                        $gametable[player]["hand"].push( $gametable[target]["hand"].shift )
                        $gametable[target]["hand"].push(old_card)
                        User(player).send "Your hand: #{$gametable[player]["hand"].first}"
                        User(target).send "Your hand: #{$gametable[target]["hand"].first}"
                    end
                when "countess"
                    Channel($game_channel).send "#{player} played and discarded the countess."
                when "princess"
                    Channel($game_channel).send "#{player} played and discarded the princess, and is eliminated for the round."
                else
                    m.reply "Something went wrong."
            end #end case
            remainingPlayers = playersRemaining()
            current_player = $players[$game_turn]
            # Check to see if round or game end conditions have been met
            if remainingPlayers.length == 1
                $gametable[remainingPlayers.first]["tokens"] += 1
                Channel($game_channel).send "The royal residence closes for the evening. Only #{remainingPlayers.first} manages to find someone to deliver their message to the Princess. #{remainingPlayers.first} has earned one token of affection from the Princess."
                $game_turn = $players.index(remainingPlayers.first)
                current_player = $players[$game_turn]
                startRound()
            elsif $deck.empty?
                playerRanks = Hash.new
                roundEnd = Array.new
                $gametable.each do |name, data|
                    if data["hand"].length < 0
                        playerRanks[name] = cardScore(data["hand"].first)
                        Channel($game_channel).send "#{name}: #{playerRanks[name]}"
                        roundEnd.push( "#{name} entrusts their letter to the #{data["hand"].first}" )
                    end
                end
                roundWinning = playerRanks.max_by{ |k, v| v }[0]
                $gametable[roundWinning]["tokens"] += 1
                $game_turn = $players.index(roundWinning)
                current_player = $players[$game_turn]
                Channel($game_channel).send "The deck is empty, ending the round. #{roundEnd.join(". ")}. The royal residence closes for the evening. The Princess retires to her chamber with #{roundWinning}'s letter in hand. #{roundWinning} has earned one token of affection from the Princess."
                startRound()
            else
                $game_turn = ($game_turn + 1) % $players.length
                # Check to see if the next person in sequence hasn't been eliminated yet
                if remainingPlayers.include? $players[$game_turn]
                    current_player = $players[$game_turn]
                elsif remainingPlayers.include? $players[($game_turn + 1) % $players.length]
                    $game_turn = ($game_turn + 1) % $players.length
                    current_player = $players[$game_turn]
                else
                    $game_turn = ($game_turn + 2) % $players.length
                    current_player = $players[$game_turn]
                end
            end
            # Check to see if anyone has won the game
            currentScores = Hash.new
            $gametable.each do |name, data|
                currentScores[name] = data["tokens"]
            end
            highscore = currentScores.max_by{ |k, v| v}
            if highscore[1] == $winningTokens
                Channel($game_channel).send "#{highscore[0]} has earned #{$winningTokens} tokens of the affection. #{highscore[0]} has won over the Princess's heart!"
                finalScores = Array.new
                currentScores.each do |name, score|
                    finalScores.push("#{name}: #{score} tokens")
                end
                Channel($game_channel).send "FINAL SCORES -- #{finalScores.join(", ")}"
                if $join_list.length > 0
                    "The game has ended, but the following people await a new game: #{join_list.join(", ")}"
                end
                resetGame()
            # if they haven't, start the next turn in the round
            else
                $game_round += 1
                Channel($game_channel).send "Current turn: #{current_player}"
                $gametable[current_player]["hand"].push($deck.shift)
                User(current_player).send "Your current cards are 0:#{$gametable[current_player]['hand'][0]} and 1:#{$gametable[current_player]['hand'][1]}. Remaining players are: #{validTargets()}. Please choose one card to play ('<3 play [id of card] [optional parameters]') Message the bot '<3 syntax [card name]' for the specific parameters of your card. Message the bot '<3 reference' for a quick look at the effects of each card type."
            end
        end
    end
end # end class

bot = Cinch::Bot.new do
	configure do |c|
		c.nick = "loveletter-bot"
		c.server = "irc.freenode.org"
		c.channels = ["#loveletter-test"]
        c.plugins.plugins = [LoveLetter]
	end
end

bot.start
