defmodule Ngram.GameState do
  @moduledoc """
  Model the game state for a tic-tac-toe game.
  """
  alias Ngram.Player
  alias __MODULE__

  defstruct code: nil,
            players: [],
            player_turn: nil,
            status: :not_started,
            timer_ref: nil,
            ngram: "",
            guesses: Map.new(),
            puzzle: [],
            prize_mult: 1,
            winnings: Map.new(),
            winner_id: nil

  @type game_code :: String.t()

  @type t :: %GameState{
          code: nil | String.t(),
          status: :not_started | :playing | :done,
          players: [Player.t()],
          player_turn: nil | integer(),
          timer_ref: nil | reference()
        }

  # 30 Minutes of inactivity ends the game
  @inactivity_timeout 1000 * 60 * 30

  @alphabet ~w(a b c d e f g h i j k l m n o p q r s t u v w x y z)
  @vowels ~w(a e i o u)

  @doc """
  Return an initialized GameState struct. Requires one player to start.
  """
  @spec new(game_code(), Player.t()) :: t()
  def new(game_code, %Player{} = player) do
    %GameState{code: game_code, players: [%Player{player | letter: "O"}], ngram: "a beautiful day in the neighborhood"}
    |> reset_inactivity_timer()
    |> update_puzzle()
    |> random_prize_mult()
  end

  defp random_prize_mult({:error, _reason} = error), do: error
  defp random_prize_mult({:ok, %GameState{} = state}), do: {:ok, random_prize_mult(state)}
  defp random_prize_mult(%GameState{} = state), do: %{state | prize_mult: Enum.random(1..12) * 100}

  defp calculate_guess_score(%GameState{} = state, letter) do
    if letter in @vowels do
      0
    else
      letter_count = state.ngram |> String.graphemes |> Enum.count(& &1 == letter)
      letter_count * state.prize_mult
    end
  end

  defp update_winnings({:error, _reason} = error, %Player{} = _player, _amount), do: error
  defp update_winnings({:ok, %GameState{} = state}, %Player{} = player, amount) do
    update_winnings(state, player, amount)
  end

  defp update_winnings(%GameState{} = state, %Player{} = player, amount) do
    winnings = state.winnings |> Map.update(player.id, amount, &(&1 + amount))
    new_winnings_amount = winnings |> Map.get(player.id)

    if new_winnings_amount >= 0 do
      {:ok, %{state | winnings: winnings}}
    else
      {:error, "Insufficient balance"}
    end
  end

  @doc """
  Guess letter
  """
  def guess_letter(%GameState{} = state, %Player{} = player, letter) do
    letter =
      if letter in @vowels do
        ""
      else
        letter
      end

    guess(state, player, letter)
  end

  @doc """
  Guess letter
  """
  def buy_vowel(%GameState{} = state, %Player{} = player, letter) do
    letter =
      if letter in @vowels do
        letter
      else
        ""
      end

    state
    |> update_winnings(player, -250)
    |> guess(player, letter)
  end

  @doc """
  Guess letter
  """
  def guess({:error, _reason} = error, _player, _letter), do: error
  def guess({:ok, %GameState{} = state}, %Player{} = player, letter), do: guess(state, player, letter)

  def guess(%GameState{} = state, %Player{} = player, letter) do
    letter = String.downcase(letter)

    # Set prize_mult to 0 if some guessed this letter
    # already. This prevents double scoring of letters.
    # Also set prize_mult to 0 if the letter is a vowel.
    prize_mult =
      cond do
        Map.has_key?(state.guesses, letter) -> 0
        letter in @vowels -> 0
        true -> state.prize_mult
      end

    # Add this letter to
    guess =
      if letter in @alphabet do
        %{letter => true}
      else
        %{}
      end

    guesses = Map.merge(state.guesses, guess)
    guess_score = calculate_guess_score(state, letter)

    state
    |> Map.put(:guesses, guesses)
    |> Map.put(:prize_mult, prize_mult)
    |> update_puzzle()
    |> verify_player_turn(player)
    |> update_winnings(player, guess_score)
    |> check_for_done()
    |> next_player_turn()
    |> random_prize_mult()
    |> reset_inactivity_timer()
  end

  def update_puzzle(%GameState{} = state) do
    hidden_letters = @alphabet -- Map.keys(state.guesses)

    puzzle =
      state.ngram
      |> String.split
      |> Enum.map(&(String.replace(&1, hidden_letters, " ") |> String.split("", trim: true)))

    %{state | puzzle: puzzle }
  end

  @doc """
  Allow another player to join the game. Exactly 2 players are required to play.
  """
  @spec join_game(t(), Player.t()) :: {:ok, t()} | {:error, String.t()}
  def join_game(%GameState{players: []} = _state, %Player{}) do
    {:error, "Can only join a created game"}
  end

  def join_game(%GameState{players: [_p1, _p2, _p3]} = _state, %Player{} = _player) do
    {:error, "Only 3 players allowed"}
  end

  def join_game(%GameState{players: [_p1]} = state, %Player{} = player) do
    {:ok, %GameState{state | players: [player | state.players]}}
  end

  def join_game(%GameState{} = state, %Player{} = player) do
    {:ok, %GameState{state | players: [player | state.players]} |> reset_inactivity_timer()}
  end

  @doc """
  Return the player from the game state found by the ID.
  """
  @spec get_player(t(), player_id :: String.t()) :: nil | Player.t()
  def get_player(%GameState{players: players} = _state, player_id) do
    Enum.find(players, &(&1.id == player_id))
  end

  @doc """
  Return the player from the game state found by the ID in an `:ok`/`:error` tuple.
  """
  @spec find_player(t(), player_id :: String.t()) :: {:ok, Player.t()} | {:error, String.t()}
  def find_player(%GameState{} = state, player_id) do
    case get_player(state, player_id) do
      nil ->
        {:error, "Player not found"}

      %Player{} = player ->
        {:ok, player}
    end
  end

  @doc """
  Return the opponent player from the perspective of the given player.
  """
  @spec opponent(t(), Player.t()) :: nil | Player.t()
  def opponent(%GameState{} = state, %Player{} = player) do
    # Find the first player that doesn't have this ID
    Enum.find(state.players, &(&1.id != player.id))
  end

  @doc """
  Start the game.
  """
  @spec start(t()) :: {:ok, t()} | {:error, String.t()}
  def start(%GameState{status: :playing}), do: {:error, "Game in play"}
  def start(%GameState{status: :done}), do: {:error, "Game is done"}

  def start(%GameState{status: :not_started, players: [_p1, _p2, _p3]} = state) do
    first_player = Enum.at(state.players, 0)

    {:ok, %GameState{state | status: :playing, player_turn: first_player.id} |> reset_inactivity_timer()}
  end

  def start(%GameState{players: _players}), do: {:error, "Missing players"}

  @doc """
  Return a boolean value for if it is currently the given player's turn.
  """
  @spec player_turn?(t(), Player.t()) :: boolean()
  def player_turn?(%GameState{player_turn: player_id}, %Player{id: id}) when player_id == id,
    do: true

  def player_turn?(%GameState{}, %Player{}), do: false

  @doc """
  Restart the game resetting the state back.
  """
  def restart(%GameState{players: [p1 | _]} = state) do
    %GameState{state | status: :playing, player_turn: p1.letter}
    |> reset_inactivity_timer()
  end

  defp verify_player_turn(%GameState{} = state, %Player{} = player) do
    if player_turn?(state, player) do
      {:ok, state}
    else
      {:error, "Not your turn!"}
    end
  end

  defp get_remaining_letters(%GameState{} = state) do
    ngram_letters =
      state.ngram
      |> String.split("", trim: true)
      |> Enum.uniq()
      |> Enum.filter(&(&1 != " "))

    guesses =
      state.guesses
      |> Map.keys()

    ngram_letters -- guesses
  end

  defp check_for_done({:ok, %GameState{} = state}) do
    state =
      case get_remaining_letters(state) do
        [] ->
          state
          |> Map.put(:status, :done)
          |> Map.put(:winner_id, state.player_turn)

        _ ->
          state
      end

    {:ok, state}
  end

  defp check_for_done({:error, _reason} = error), do: error

  defp next_player_turn({:error, _reason} = error), do: error

  defp next_player_turn({:ok, %GameState{player_turn: player_turn} = state}) do
    # Find current index, increment it, the mod with the players length
    next_index = (1 + Enum.find_index(state.players, &(&1.id == player_turn)))
    next_index = rem(next_index, length(state.players))
    next_player = Enum.at(state.players, next_index)
    {:ok, %GameState{state | player_turn: next_player.id}}
  end

  defp reset_inactivity_timer({:error, _reason} = error), do: error

  defp reset_inactivity_timer({:ok, %GameState{} = state}) do
    {:ok, reset_inactivity_timer(state)}
  end

  defp reset_inactivity_timer(%GameState{} = state) do
    state
    |> cancel_timer()
    |> set_timer()
  end

  defp cancel_timer(%GameState{timer_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %GameState{state | timer_ref: nil}
  end

  defp cancel_timer(%GameState{} = state), do: state

  defp set_timer(%GameState{} = state) do
    %GameState{
      state
      | timer_ref: Process.send_after(self(), :end_for_inactivity, @inactivity_timeout)
    }
  end
end
