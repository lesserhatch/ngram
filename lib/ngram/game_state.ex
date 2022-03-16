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
            guessed_letters: [],
            hint: ""

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

  @doc """
  Return an initialized GameState struct. Requires one player to start.
  """
  @spec new(game_code(), Player.t()) :: t()
  def new(game_code, %Player{} = player) do
    %GameState{code: game_code, players: [%Player{player | letter: "O"}], ngram: "a beautiful day in the neighborhood"}
    |> reset_inactivity_timer()
    |> update_hint()
  end

  @doc """
  Guess letter
  """
  def guess_letter(%GameState{} = state, %Player{} = player, letter) do
    # TODO: Handle case where letter == vowel
    # TODO: Handle case where letter is already guessed
    state = %{ state | guessed_letters: [letter | state.guessed_letters] }

    state
    |> update_hint()
    |> verify_player_turn(player)
    |> check_for_done()
    |> next_player_turn()
    |> reset_inactivity_timer()
  end

  def update_hint(%GameState{} = state) do
    %{state | hint: String.replace(state.ngram, @alphabet -- state.guessed_letters, "_") }
  end

  @doc """
  Allow another player to join the game. Exactly 2 players are required to play.
  """
  @spec join_game(t(), Player.t()) :: {:ok, t()} | {:error, String.t()}
  def join_game(%GameState{players: []} = _state, %Player{}) do
    {:error, "Can only join a created game"}
  end

  def join_game(%GameState{players: [_p1, _p2]} = _state, %Player{} = _player) do
    {:error, "Only 2 players allowed"}
  end

  def join_game(%GameState{players: [p1]} = state, %Player{} = player) do
    player =
      if p1.letter == "O" do
        %Player{player | letter: "X"}
      else
        %Player{player | letter: "O"}
      end

    {:ok, %GameState{state | players: [p1, player]} |> reset_inactivity_timer()}
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

  def start(%GameState{status: :not_started, players: [_p1, _p2]} = state) do
    {:ok, %GameState{state | status: :playing, player_turn: "O"} |> reset_inactivity_timer()}
  end

  def start(%GameState{players: _players}), do: {:error, "Missing players"}

  @doc """
  Return a boolean value for if it is currently the given player's turn.
  """
  @spec player_turn?(t(), Player.t()) :: boolean()
  def player_turn?(%GameState{player_turn: turn}, %Player{letter: letter}) when turn == letter,
    do: true

  def player_turn?(%GameState{}, %Player{}), do: false

  @doc """
  Check to see if the player won. Return a tuple of the winning squares if the they won. If no win found, returns `:not_found`.

  Tests for all the different ways the player could win.
  """
  @spec check_for_player_win(t(), Player.t()) :: :not_found | [atom()]
  def check_for_player_win(%GameState{} = _state, %Player{letter: _letter}) do
    # TODO: define player win logic
    :not_found
  end

  @doc """
  Check for who the game's result. Either a player won, the game ended in a
  draw, or the game is still going.
  """
  @spec result(t()) :: :playing | :draw | Player.t()
  def result(%GameState{players: [p1, p2]} = state) do
    player_1_won =
      case check_for_player_win(state, p1) do
        :not_found -> false
        [_, _, _] -> true
      end

    player_2_won =
      case check_for_player_win(state, p2) do
        :not_found -> false
        [_, _, _] -> true
      end

    cond do
      player_1_won -> p1
      player_2_won -> p2
      true -> :playing
    end
  end

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

  defp check_for_done({:ok, %GameState{} = state}) do
    case result(state) do
      :playing ->
        {:ok, state}

      _game_done ->
        {:ok, %GameState{state | status: :done}}
    end
  end

  defp check_for_done({:error, _reason} = error), do: error

  defp next_player_turn({:error, _reason} = error), do: error

  defp next_player_turn({:ok, %GameState{player_turn: turn} = state}) do
    {:ok, %GameState{state | player_turn: if(turn == "X", do: "O", else: "X")}}
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
