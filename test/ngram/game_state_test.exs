defmodule Ngram.GameStateTest do
  use ExUnit.Case
  import Ngram.Fixtures

  doctest Ngram.GameState

  alias Ngram.GameState
  alias Ngram.Player

  @game_code "ABCD"

  setup do
    player = fixture(:player, %{letter: "O"})
    opponent = fixture(:player, %{letter: "X"})
    %{players: [player, opponent], player: player}
  end

  # TODO: Test check_for_player_win/2
  # describe "check_for_player_win/2" do
  # end

  describe "new/2" do
    test "sets the game_code and the player" do
      uuid = Ecto.UUID.generate()
      state = GameState.new("1234", %Player{id: uuid, name: "Tom", letter: nil})
      assert state.code == "1234"
      assert [p1] = state.players
      assert p1.id == uuid
      assert p1.name == "Tom"
      # Player is auto-assigned letter
      assert p1.letter == "O"
    end

    test "sets a timer to start inactivity check", %{players: [p1, _p2]} do
      state = GameState.new("1234", p1)
      assert state.timer_ref != nil
      assert is_reference(state.timer_ref)
    end
  end

  describe "join_game/2" do
    test "second player can join", %{players: [p1, p2]} do
      state = GameState.new(@game_code, p1)
      assert {:ok, new_state} = GameState.join_game(state, p2)
      assert length(new_state.players) == 2
    end

    test "deny more than 2 players", %{players: [p1, p2]} do
      state = GameState.new(@game_code, p1)
      assert {:ok, new_state} = GameState.join_game(state, p2)

      assert {:error, "Only 2 players allowed"} =
               GameState.join_game(new_state, %Player{name: "Fran", letter: "X"})
    end

    test "make 2nd player be opposing letter", %{players: [p1, p2]} do
      assert p1.letter == "O"
      assert p2.letter == "X"
      # Try to add second player also as letter "O"
      p2 = %Player{p2 | letter: "O"}
      state = GameState.new(@game_code, p1)
      assert {:ok, new_state} = GameState.join_game(state, p2)
      [_p1, added_p2] = new_state.players
      assert added_p2.letter == "X"
    end

    test "errors joining a game that wasn't started by a player", %{players: [p1, _]} do
      state = %GameState{}
      assert {:error, "Can only join a created game"} == GameState.join_game(state, p1)
    end

    test "resets timer_ref", %{players: [p1, p2]} do
      state = GameState.new(@game_code, p1)
      assert {:ok, new_state} = GameState.join_game(state, p2)
      assert is_reference(new_state.timer_ref)
      assert new_state.timer_ref != state.timer_ref
    end
  end

  describe "start/1" do
    test "when 2 players and not already started, set status to playing", %{players: players} do
      [p1 | _] = players
      state = %GameState{status: :not_started, players: players}
      assert {:ok, new_state} = GameState.start(state)
      assert new_state.status == :playing
      assert new_state.player_turn == p1.letter
    end

    test "a new game starts with O player", %{players: [p1, p2]} do
      # Verify that player1 is O
      assert p1.letter == "O"
      assert p2.letter == "X"
      # Start with player2 who is currently "X"
      {:ok, state} =
        @game_code
        |> GameState.new(p2)
        |> GameState.join_game(p1)

      {:ok, game} = GameState.start(state)
      assert game.status == :playing
      assert game.player_turn != nil

      refute GameState.player_turn?(game, p2)
      assert GameState.player_turn?(game, p1)
    end

    test "reject when already playing", %{players: players} do
      state = %GameState{status: :playing, players: players}
      assert {:error, "Game in play"} == GameState.start(state)
    end

    test "reject when don't missing players", %{players: [p1, _]} do
      state = %GameState{status: :not_started, players: []}
      assert {:error, "Missing players"} == GameState.start(state)

      state = %GameState{status: :not_started, players: [p1]}
      assert {:error, "Missing players"} == GameState.start(state)
    end

    test "can't start when done", %{players: players} do
      state = %GameState{status: :done, players: players}
      assert {:error, "Game is done"} == GameState.start(state)
    end

    test "resets the timer_ref", %{players: [p1, p2]} do
      state = GameState.new(@game_code, p1)
      {:ok, joined_state} = GameState.join_game(state, p2)
      {:ok, started_state} = GameState.start(joined_state)
      assert is_reference(started_state.timer_ref)
      assert joined_state.timer_ref != started_state.timer_ref
    end
  end

  describe "get_player/2" do
    test "returns nil when not found", %{players: [p1, p2]} do
      state = %GameState{players: [p1, p2]}
      assert nil == GameState.get_player(state, Ecto.UUID.generate())
    end

    test "returns the player when string ID is given", %{players: [p1, p2]} do
      state = %GameState{players: [p1, p2]}
      assert p1 == GameState.get_player(state, to_string(p1.id))
    end

    test "returns player when player's UUID is given", %{players: [p1, p2]} do
      state = %GameState{players: [p1, p2]}
      assert p2 == GameState.get_player(state, p2.id)
    end
  end

  describe "find_player/2" do
    test "returns error when not found", %{players: [p1, p2]} do
      state = %GameState{players: [p1, p2]}
      assert {:error, "Player not found"} == GameState.find_player(state, Ecto.UUID.generate())
    end

    test "returns the player when string ID is given", %{players: [p1, p2]} do
      state = %GameState{players: [p1, p2]}
      assert {:ok, p1} == GameState.find_player(state, to_string(p1.id))
    end
  end

  describe "opponent/2" do
    test "returns nil when no opponent", %{players: [p1, _p2]} do
      state = %GameState{players: [p1]}
      assert nil == GameState.opponent(state, p1)
    end

    test "returns the other player", %{players: [p1, p2]} do
      state = %GameState{players: [p1, p2]}
      assert p2 == GameState.opponent(state, p1)
      assert p1 == GameState.opponent(state, p2)
    end
  end

  describe "player_turn?/2" do
    test "correctly identifies when it's the player's turn", %{players: [p1, p2]} do
      state = %GameState{players: [p1, p2], player_turn: "O"}
      assert GameState.player_turn?(state, p1)
      refute GameState.player_turn?(state, p2)

      state = %GameState{players: [p1, p2], player_turn: "X"}
      refute GameState.player_turn?(state, p1)
      assert GameState.player_turn?(state, p2)
    end
  end

  describe "restart/1" do
    setup %{players: [p1, p2]} do
      {:ok, game} =
        @game_code
        |> GameState.new(p1)
        |> GameState.join_game(p2)

      {:ok, game} = GameState.start(game)
      %{game: game}
    end

    test "status is :playing", %{game: game} do
      game_done = %GameState{game | status: :done}
      updated = GameState.restart(game_done)
      assert updated.status == :playing
    end

    # TODO: Test game restart logic
    # test "game is restarted", %{game: game, players: [p1, p2]} do
    #   {:ok, played} = GameState.move(game, p1, :sq11)
    #   assert played.player_turn == p2.letter
    #   updated = GameState.restart(played)
    #   # player turn is player 1
    #   assert updated.player_turn == p1.letter
    #   # the board is reset
    #   assert updated.board == %GameState{}.board
    # end

    test "resets the timer_ref", %{game: game} do
      restarted_state = GameState.restart(game)
      assert is_reference(restarted_state.timer_ref)
      assert game.timer_ref != restarted_state.timer_ref
    end
  end

  describe "full game run through" do
    test "a full winning game works", %{players: [p1, p2]} do
      {:ok, game} =
        @game_code
        |> GameState.new(p1)
        |> GameState.join_game(p2)

      {:ok, _game} = GameState.start(game)

      # TODO: Test full game run through
      # game
      # |> assert_player_turn(p1)
      # |> GameState.move(p1, :sq11)
      # |> assert_player_turn(p2)
      # |> assert_square_letter(:sq11, "O")
      # |> assert_status(:done)
      # |> assert_result(p1)
    end
  end

  # TODO: Enable these for testing the full game run through
  # defp assert_status({:ok, %GameState{status: status} = state}, expected) do
  #   assert status == expected
  #   {:ok, state}
  # end

  # defp assert_player_turn(%GameState{} = state, %Player{} = player) do
  #   assert GameState.player_turn?(state, player)
  #   state
  # end

  # defp assert_player_turn({:ok, %GameState{} = state}, %Player{} = player) do
  #   assert_player_turn(state, player)
  #   {:ok, state}
  # end

  # defp assert_result({:ok, %GameState{} = state}, result_value) do
  #   assert result_value == GameState.result(state)
  #   {:ok, state}
  # end
end
