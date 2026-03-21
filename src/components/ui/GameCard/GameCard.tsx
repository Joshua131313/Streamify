import React from "react";
import type { IGame } from "../../../types/sports";
import "./GameCard.css"
import { Button } from "../Button/Button";

type Props = {
    game: IGame;
    setPlayerSrc: (s: string) => void;
    showTag?: boolean;
};

const GameCard: React.FC<Props> = ({ game, setPlayerSrc, showTag }) => {

    
    return (
        <div className="game-card">
            <div className="inner-game-card">
                <div className="game-card-badges">
                    {
                        game.status === "live" ?
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
            <Button className="watch-btn" onClick={() => setPlayerSrc(game.stream + "&autoplay=1")}>
                Watch
            </Button>
        </div>
    );
};

export default GameCard;