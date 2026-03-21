import React from "react";
import type { IGame } from "../../../types/sports";
import "./GameCard.css"
import { Button } from "../Button/Button";
import { getGameStatus } from "../../../utils/sports";
import { WatchButton } from "../Button/WatchButton";

type Props = {
    game: IGame;
    showTag?: boolean;
};

const GameCard: React.FC<Props> = ({ game, showTag }) => {

    
    return (
        <div className="game-card">
            <div className="inner-game-card">
                <div className="game-card-badges">
                    {
                        getGameStatus(game.date) === "live" ?
                            <div className="live-badge">● LIVE</div>
                        :
                            <div className="not-started-badge">Not started</div>
                    }
                    {showTag && <div className="sport-tag">Basketball</div>}
                </div>

                {/* Logos */}
                <div className="logos">
                    <img src={game.homeTeam.logo} alt={game.homeTeam.name} />
                    <span className="vs">vs</span>
                    <img src={game.awayTeam.logo} alt={game.awayTeam.name} />
                </div>
                <div className="game-info">
                    <div className="game-title">{game.game}</div>
                    <div className="game-time">
                        {new Date(game.date).toLocaleTimeString([], {
                            hour: "2-digit",
                            minute: "2-digit"
                        })}
                    </div>
                </div>
            </div>
            <WatchButton 
                variant="button"
                channel={game.channel}
                streamProvider={game.streamProvider}
            />
        </div>
    );
};

export default GameCard;