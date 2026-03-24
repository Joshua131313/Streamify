import React, { useContext, useState } from "react";
import "./GameCard.css";
import { getWatchURL, WatchButton } from "../Button/WatchButton";
import type { GameProps, GameStatus, TStreamProvider } from "../../../types/sports/sportsTypes";
import ExternalGameInfoButton from "../Button/ExternalGameInfoButton";
import { useSports } from "../../../context/SportsContext";
import { useContextMenu } from "../../../context/ContextMenu";
import type { ContextMenuOption } from "../../../types";
import { FaBell, FaCubes, FaExternalLinkAlt, FaPlay, FaThLarge } from "react-icons/fa";
import { useNavigate } from "react-router-dom";


interface Props {
    game: GameProps;
    showSportName?: boolean;
}

const GameCard: React.FC<Props> = ({ game, showSportName }) => {
    const { setQuickWatch } = useSports();
    const { openMenu } = useContextMenu();
    const navigate = useNavigate();
    const mediaCardContextOptions: ContextMenuOption[] = [
        {
            key: "watch",
            value: "Watch",
            icon: FaPlay,
            onClick: () => navigate(getWatchURL({ channel: game.channel, streamProvider: game.streamProvider }))
        },
        {
            key: "multi-watch",
            value: "Multi-Watch",
            icon: FaThLarge,
            onClick: () => setQuickWatch(prev => [...prev, game]),
        },
        {
            key: "new-tab",
            value: "Watch in New Tab",
            icon: FaExternalLinkAlt,
            onClick: () => {
                const url = getWatchURL({
                    channel: game.channel,
                    streamProvider: game.streamProvider
                });

                window.open(url, "_blank", "noopener,noreferrer");
            }
        },
        {
            key: "notify",
            value: "Notify when live",
            icon: FaBell,
            onClick: () => addNotification(),
        }
    ]
    // dummy notifications system for now
    const addNotification = () => {
        // 1. Ask permission
        if (Notification.permission === "default") {
            Notification.requestPermission().then(permission => {
                if (permission === "granted") {
                    schedule();
                }
            });
        } else if (Notification.permission === "granted") {
            schedule();
        } else {
            alert("Notifications are blocked");
        }
        function schedule() {
            const gameTime = new Date(game.startTime).getTime();
            const now = Date.now();

            const delay = gameTime - now;

            if (delay <= 0) {
                alert("Game already started");
                return;
            }

            setTimeout(() => {
                new Notification(`${game.homeTeam.name} vs ${game.awayTeam.name}`, {
                    body: "Game is starting now!",
                });
            }, delay);

        }
    };
    const showScore = (game: GameProps, key: "awayTeam" | "homeTeam") => {
        return game[key].score !== undefined && (game.status === "FINAL" || game.status === "LIVE" || game.status === "HALFTIME") // score is not null and game is either finished or live
    }

    const StatusBadge = () => {
        if (game.status === "LIVE" || game.status === "HALFTIME") {
            return <div className="status-tag">{game.periodNumber} {game.clock && ": " + game.clock}</div>
        }
        else if (game.status === "FINAL") {
            return null;
        }
        else {
            return (
                <div className="status-tag">
                    {new Date(game.startTime).toLocaleTimeString([], {
                        hour: "2-digit",
                        minute: "2-digit",
                    })}
                </div>
            )
        }
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

                    <StatusBadge />
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
            </div>

            {/* 🔥 Watch button */}
            <div className="game-card-buttons flex-row">
                <ExternalGameInfoButton url={game.gameLink} />
                <WatchButton
                    variant="button"
                    channel={game.channel}
                    streamProvider={game.streamProvider}
                    onContextMenu={(e) => openMenu({
                        options: mediaCardContextOptions,
                        e
                    })}
                />
            </div>
        </div>
    );
};

export default GameCard;