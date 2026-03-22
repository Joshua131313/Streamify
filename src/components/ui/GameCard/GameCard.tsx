import React from "react";
import "./GameCard.css";
import { WatchButton } from "../Button/WatchButton";
import type { GameStatus, TStreamProvider } from "../../../types/sports/sportsTypes";

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

    sportName: "Basketball" | "Hockey";
    streamProvider: TStreamProvider;
    channel: string;
}

interface Props {
    game: GameProps;
    showSportName?: boolean;
}

const GameCard: React.FC<Props> = ({ game, showSportName }) => {
    const isLive = game.status === "LIVE";

    return (
        <div className="game-card">
            <div className="inner-game-card">

                {/* 🔥 Badges */}
                <div className="game-card-badges">
                    {game.status === "LIVE" ? (
                        <div className="live-badge">● LIVE</div>
                    ) : game.status === "PRE" ? (
                        <div className="not-started-badge">Pre Game</div>
                    ) : game.status === "FINAL" ? (
                        <div className="not-started-badge">Final</div>
                    ) : (
                        <div className="not-started-badge">Upcoming</div>
                    )}

                    {showSportName && (
                        <div className="sport-tag">{game.sportName}</div>
                    )}
                </div>

                {/* 🔥 Logos + Score */}
                <div className="logos">
                    <div className="team">
                        <img src={game.homeTeam.logo} alt={game.homeTeam.name} />
                        {(game.homeTeam.score !== undefined && game.status === "LIVE") ? (
                            <div className="score">{game.homeTeam.score}</div>
                        ) : (
                            <div className="score ghost-score">-</div>
                        )
                        }
                    </div>

                    <span className="vs">vs</span>

                    <div className="team">
                        <img src={game.awayTeam.logo} alt={game.awayTeam.name} />
                        {(game.awayTeam.score !== undefined && game.status === "LIVE") ? (
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
                    {!isLive ? (
                        <div className="game-time">
                            {new Date(game.startTime).toLocaleDateString([], {
                                hour: "2-digit",
                                minute: "2-digit",
                            })}
                        </div>
                    ) : (
                        <div className="live-info">
                            <span>
                                {game.period && `${game.period}, `}
                                {game.periodNumber && `Period: ${game.periodNumber}`}
                            </span>
                            {game.period && <span>{game.period}, Period: {game.periodNumber}</span>}
                            {game.clock && <span> • {game.clock}</span>}
                        </div>
                    )}
                </div>
            </div>

            {/* 🔥 Watch button */}
            <WatchButton
                variant="button"
                channel={game.channel}
                streamProvider={game.streamProvider}
            />
        </div>
    );
};

export default GameCard;