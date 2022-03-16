defmodule NgramWeb.LiveView.Components do
  @moduledoc """
  Collection of components for rendering game elements.
  """
  use Phoenix.HTML
  alias Ngram.GameState
  alias Ngram.Player

  def player_tile_color(%GameState{status: :done} = game, player, _local_player) do
    case GameState.result(game) do
      :draw ->
        "bg-gray-400"

      # If the winner is this player
      ^player ->
        "bg-green-400"

      # If the losing player
      %Player{} ->
        "bg-red-400"

      _else ->
        "bg-gray-400"
    end
  end

  def player_tile_color(%GameState{status: :playing} = game, player, local_player) do
    if GameState.player_turn?(game, player) do
      if player == local_player do
        "bg-green-400"
      else
        "bg-gray-400"
      end
    else
      "bg-gray-400"
    end
  end

  def result(%GameState{status: :done} = state) do
    text =
      case GameState.result(state) do
        :draw ->
          "Tie Game!"

        %Player{name: winner_name} ->
          "#{winner_name} Wins!"
      end

    ~E"""
    <div class="m-4 sm:m-8 text-3xl sm:text-6xl text-center text-green-700">
      <%= text %>
    </div>
    """
  end

  def result(%GameState{} = _state) do
    ~E"""
    """
  end
end
