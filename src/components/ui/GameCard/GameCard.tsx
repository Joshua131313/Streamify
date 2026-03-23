import React from "react";
import "./GameCard.css";
import { WatchButton } from "../Button/WatchButton";
import type { GameStatus, TStreamProvider } from "../../../types/sports/sportsTypes";
import ExternalGameInfoButton from "../Button/ExternalGameInfoButton";

export interface GameTeam {
    name: string;
    logo: string;
    score?: number;
}

export interface GameProps {
    id?: string | number;
    title: string;

    homeTeam: GameTeam;
    awayTeam: GameTeam;

    startTime: string;
    status: GameStatus;

    period?: string;
    periodNumber?: string;
    clock?: string;
    gameLink: string;
    sportName: "Basketball" | "Hockey";
    streamProvider: TStreamProvider;
    channel: string;
}

interface Props {
    game: GameProps;
    showSportName?: boolean;
}

const GameCard: React.FC<Props> = ({ game, showSportName }) => {
    const showScore = (game: GameProps, key: "awayTeam" | "homeTeam") => {
        return game[key].score !== undefined && (game.status === "FINAL" || game.status === "LIVE" || game.status === "HALFTIME") // score is not null and game is either finished or live
    }

    return (
        <div className="game-card">
            <div className="inner-game-card">

                {/* 🔥 Badges */}
                <div className="game-card-badges">
                    {(game.status === "LIVE" || game.status === "HALFTIME") ? (
                        <div className="live-badge">● {game.status}</div>
                    ) : game.status === "PRE" ? (
                        <div className="not-started-badge">Pre Game</div>
                    ) : game.status === "FINAL" ? (
                        <div className="not-started-badge">Final</div>
                    ) : (
                        <div className="not-started-badge">Upcoming</div>
                    )}

                    {(game.status === "LIVE" || game.status === "HALFTIME") ? (
                        <div className="status-tag">{game.periodNumber} {game.clock && ": " + game.clock}</div>
                    )
                        : (
                            <div className="status-tag">
                                {new Date(game.startTime).toLocaleTimeString([], {
                                    hour: "2-digit",
                                    minute: "2-digit",
                                })}
                            </div>

                        )}
                </div>

                {/* 🔥 Logos + Score */}
                <div className="logos">
                    <div className="team">
                        <img src={game.homeTeam.logo} alt={game.homeTeam.name} />
                        {(showScore(game, "homeTeam")) ? (
                            <div className="score">{game.homeTeam.score}</div>
                        ) : (
                            <div className="score ghost-score">-</div>
                        )
                        }
                    </div>

                    <span className="vs">vs</span>

                    <div className="team">
                        <img src={game.awayTeam.logo} alt={game.awayTeam.name} />
                        {(showScore(game, "awayTeam")) ? (
                            <div className="score">{game.awayTeam.score}</div>
                        ) : (
                            <div className="score ghost-score">-</div>
                        )}
                    </div>
                </div>

                {/* 🔥 Info */}
                <div className="game-info">
                    <div className="game-title">{game.title}</div>

                    {/* time OR live info */}
                    {/* {!isLive && (
                        <div className="game-time">
                            {new Date(game.startTime).toLocaleDateString([], {
                                hour: "2-digit",
                                minute: "2-digit",
                            })}
                        </div>
                    )} */}
                </div>
            </div>

            {/* 🔥 Watch button */}
            <div className="game-card-buttons flex-row">
                <ExternalGameInfoButton url={game.gameLink} />
                <WatchButton
                    variant="button"
                    channel={game.channel}
                    streamProvider={game.streamProvider}
                />
            </div>
        </div>
    );
};

export default GameCard;