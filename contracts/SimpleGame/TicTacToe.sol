// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

contract TicTacToe {
    /**
     * @dev game board design:
     * 21bits to represent a game board: 18 bits for board, 2 bits for game state and 1 bit for turn
     * 00 00 00 |
     * 00 00 00 | = first 18 bits
     * 00 00 00 |
     *
     * [00] [0] [00 00 00 00 00 00 00 00 00]
     *
     * State: 10 - game ongoing; 00 - player 1 win; 01 - player 2 win; 11 - draw
     * Turn: 0 for player1, 1 for player2
     */

    //     1. 00 00 00
    //        00 00 00
    //        11 11 11
    //     => 0b111111 = 0x3F
    uint256 internal constant HORIZONTAL_MASK = 0x3F;
    //     2. 00 00 11
    //        00 00 11
    //        00 00 11
    //     => 0b11000011000011 = 0x30C3
    uint256 internal constant VERTICAL_MASK = 0x30C3;
    //     3. 11 00 00
    //        00 11 00
    //        00 00 11
    //     => 0b110000001100000011 = 0x30303
    uint256 internal constant BR_TO_TL_DIAGONAL_MASK = 0x30303;
    //     4. 00 00 11
    //        00 11 00
    //        11 00 00
    //     => 0b1100110011 = 0x3330
    uint256 internal constant BL_TO_TR_DIAGONAL_MASK = 0x3330;

    struct Game {
        uint256 gameBoard;
        address player1;
        address player2;
    }

    mapping(uint256 => Game) public gameById;
    uint256 public gameId = 0;

    event NewGame(uint256 indexed gameId, address player1, address player2);
    event PlayerWin(uint256 indexed gameId, address player);
    event Draw(uint256 indexed gameId);

    modifier isPlayer(uint256 _gameId) {
        require(
            msg.sender == gameById[_gameId].player1 || msg.sender == gameById[_gameId].player2,
            "you are not the player"
        );
        _;
    }

    function createNewGame(address _player1, address _player2) external {
        uint256 initialGameBoard = 0 | (1 << 20);
        gameById[gameId] = Game(initialGameBoard, _player1, _player2);
        emit NewGame(gameId, _player1, _player2);
        gameId++;
    }

    function makeMove(uint256 _move, uint256 _gameId) external isPlayer(_gameId) {
        Game memory game = gameById[_gameId];
        uint256 currentPlayerId = (game.gameBoard >> 18) & 0x1;
        uint256 playerId = msg.sender == game.player1 ? 0 : 1;
        require(currentPlayerId == playerId, "Not your turn");

        uint256 _gameBoard = game.gameBoard;
        require((_gameBoard >> 19) & 1 == 0 && (_gameBoard >> 20) & 1 == 1, "Game has ended");

        uint256 p1 = _move << 1;
        uint256 p2 = p1 + 1;
        require(!(((_gameBoard >> p1) & 1) == 1 || ((_gameBoard >> p2) & 1) == 1), "invalid move");
        require(_move < 9, "invalid move");

        // making the move in _gameboard: 01 for player 1 move, 10 for player 2 move;
        _gameBoard = _gameBoard ^ (1 << ((_move << 1) + playerId));

        // Change the turn
        game.gameBoard = _gameBoard ^ (1 << 18);

        uint256 gameState = _checkState(playerId, game.gameBoard);

        // 0 => continue to play; 1 => current player win; 2 => no more fields to play, draw;
        if (gameState == 1) {
            if (playerId == 0) {
                game.gameBoard = game.gameBoard ^ (1 << 20);
                emit PlayerWin(_gameId, game.player1);
            } else {
                uint256 mask = (1 << 20) | (1 << 19);
                game.gameBoard = game.gameBoard ^ mask;
                emit PlayerWin(_gameId, game.player2);
            }
        } else if (gameState == 2) {
            game.gameBoard = game.gameBoard ^ (1 << 19);
            emit Draw(_gameId);
        }
        gameById[_gameId] = game;
    }

    function getCurrentBoard(uint256 _gameId) public view returns (uint256) {
        return gameById[_gameId].gameBoard;
    }

    function _checkState(uint256 _playerId, uint256 _gameBoard) internal pure returns (uint256) {
        //HORIZONTAL wins
        if ((_gameBoard & HORIZONTAL_MASK) == ((HORIZONTAL_MASK / 3) << _playerId)) {
            return 1;
        } else if ((_gameBoard & (HORIZONTAL_MASK << 6)) == ((HORIZONTAL_MASK / 3) << _playerId) << 6) {
            return 1;
        } else if ((_gameBoard & (HORIZONTAL_MASK << 12)) == ((HORIZONTAL_MASK / 3) << _playerId) << 12) {
            return 1;
        }

        //VERTICAL wins
        if ((_gameBoard & VERTICAL_MASK) == (VERTICAL_MASK / 3) << _playerId) {
            return 1;
        } else if ((_gameBoard & (VERTICAL_MASK << 2)) == ((VERTICAL_MASK / 3) << _playerId) << 2) {
            return 1;
        } else if ((_gameBoard & (VERTICAL_MASK << 4)) == ((VERTICAL_MASK / 3) << _playerId) << 4) {
            return 1;
        }

        //DIAGONAL wins
        if ((_gameBoard & BR_TO_TL_DIAGONAL_MASK) == (BR_TO_TL_DIAGONAL_MASK / 3) << _playerId) {
            return 1;
        }
        if ((_gameBoard & BL_TO_TR_DIAGONAL_MASK) == (BL_TO_TR_DIAGONAL_MASK / 3) << _playerId) {
            return 1;
        }

        unchecked {
            /// Checks if all fields has been played
            for (uint256 x = 0; x < 9; x++) {
                if (_gameBoard & 1 == 0 && _gameBoard & 2 == 0) {
                    return 0;
                }
                _gameBoard = _gameBoard >> 2;
            }

            /// A Draw
            return 2;
        }
    }
}
