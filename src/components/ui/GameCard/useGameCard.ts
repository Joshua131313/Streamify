import { useNavigate } from "react-router-dom";
import { DateTime } from "luxon";
import {
    FaBell,
    FaExternalLinkAlt,
    FaEyeSlash,
    FaPlay,
    FaThLarge,
} from "react-icons/fa";

import type { MenuOption } from "../../../types";
import type { GameProps, TStreamProvider } from "../../../types/sports/sportsTypes";

import { useContextMenu } from "../../../context/ContextMenu";
import { useMultiWatch } from "../../../context/MultiWatchContext";
import { useWindowManager } from "../../../context/WindowManagerContext";

import { getWatchURL } from "../Button/WatchButton";
import { gameIsWatchable, getSportStream } from "../../../utils/sports/sportsUtils";
import { requestNotificationPermission } from "../../../firebase/notifications";

export interface UseGameCardReturn {
    watchURL: string;
    defaultSportStreamProvider: TStreamProvider;
    showPlayButtons: boolean;
    gameInMultiWatch: boolean;
    openContextMenu: (e: React.MouseEvent<HTMLDivElement>) => void;
    addNotification: () => void;
    badgeLabel: string;
    statusDetail: string | null;
    leadingTeam: "homeTeam" | "awayTeam";
}

export const useGameCard = (game: GameProps): UseGameCardReturn => {
    const { toggleGameInMultiWatch, isGameInMultiWatch } = useMultiWatch();
    const { openWindow, minimizeWindow, windowIsOpen, windows } = useWindowManager();
    const { openMenu } = useContextMenu();
    const navigate = useNavigate();

    const defaultSportStream = getSportStream(game.leagueName)[0];
    const defaultSportStreamProvider = defaultSportStream.provider;

    const watchURL = getWatchURL({
        league: game.leagueName,
        awayTeamAbbrev: game.awayTeam.abbrev,
        homeTeamAbbrev: game.homeTeam.abbrev,
        streamProvider: defaultSportStreamProvider,
    });

    const showPlayButtons = gameIsWatchable(game.startTime, game.status);
    const gameInMultiWatch = isGameInMultiWatch(game);
    const leadingTeam = (game.awayTeam.score ?? 0) > (game.homeTeam.score ?? 0) ? "awayTeam" : "homeTeam"

    const addNotification = async () => {
        const token = await requestNotificationPermission();
        if(!token) {
            console.log("failed to enable notifications")
        }
        await fetch("/api/subscribe-game", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                token,
                gameId: game.id,
                home: game.homeTeam.name,
                away: game.awayTeam.name,
                startTime: game.startTime
            })
        })
        
        // if (Notification.permission === "default") {
        //     Notification.requestPermission().then((permission) => {
        //         if (permission === "granted") {
        //             schedule();
        //         }
        //     });
        // } else if (Notification.permission === "granted") {
        //     schedule();
        // } else {
        //     alert("Notifications are blocked");
        // }

        // function schedule() {
        //     const gameTime = new Date(game.startTime).getTime();
        //     const now = Date.now();
        //     const delay = gameTime - now;

        //     if (delay <= 0) {
        //         alert("Game already started");
        //         return;
        //     }

        //     setTimeout(() => {
        //         new Notification(`${game.homeTeam.name} vs ${game.awayTeam.name}`, {
        //             body: "Game is starting now!",
        //         });
        //     }, delay);
        // }
    };

    const mediaCardContextOptions: MenuOption[] = [
        ...(showPlayButtons
            ? [
                {
                    key: "watch",
                    value: "Watch",
                    icon: FaPlay,
                    onClick: () => navigate(watchURL),
                },
                {
                    key: "new-window",
                    value: windowIsOpen(watchURL)
                        ? "Hide watch window"
                        : "Watch in New Window",
                    icon: windowIsOpen(watchURL) ? FaEyeSlash : FaPlay,
                    onClick: () => {
                        const state = windows[watchURL]?.windowState;

                        if (state === "opened" || state === "fullscreen") {
                            minimizeWindow(watchURL);
                        } else {
                            openWindow(watchURL, "opened");
                        }
                    },
                },
                {
                    key: "multi-watch",
                    value: gameInMultiWatch
                        ? "Remove from Multi-Watch"
                        : "Add to Multi-Watch",
                    icon: FaThLarge,
                    onClick: () => {
                        toggleGameInMultiWatch(game);
                        if (!gameInMultiWatch) {
                            openWindow("multiwatch", "opened");
                        }
                    },
                },
                {
                    key: "new-tab",
                    value: "Watch in New Tab",
                    icon: FaExternalLinkAlt,
                    onClick: () => {
                        window.open(watchURL, "_blank", "noopener,noreferrer");
                    },
                },
            ]
            : []),

        ...((game.status === "PRE" || game.status === "FUT")
            ? [
                {
                    key: "notify",
                    value: "Notify when live",
                    icon: FaBell,
                    onClick: () => addNotification(),
                },
            ]
            : []),
    ];

    const openContextMenu = (e: React.MouseEvent<HTMLDivElement>) => {
        openMenu({
            options: mediaCardContextOptions,
            e,
        });
    };

    const badgeLabel =
        game.status === "LIVE" || game.status === "HALFTIME"
            ? `● ${game.status}`
            : game.status === "PRE"
                ? "Pre Game"
                : game.status === "FINAL"
                    ? "Final"
                    : DateTime.fromISO(game.startTime).toRelative() ?? "Upcoming";

    const statusDetail =
        game.status === "LIVE" || game.status === "HALFTIME"
            ? game.leagueName === "MLB"
                ? `${game.clock?.toUpperCase() ?? ""} ${game.periodNumber ?? ""}`.trim()
                : `${game.periodNumber === "P4" ? "OT" : game.periodNumber ?? ""}${game.clock ? `: ${game.clock}` : ""
                    }`.trim()
            : game.status === "FINAL"
                ? null
                : new Date(game.startTime).toLocaleTimeString([], {
                    hour: "2-digit",
                    minute: "2-digit",
                });

    return {
        watchURL,
        defaultSportStreamProvider,
        showPlayButtons,
        gameInMultiWatch,
        openContextMenu,
        addNotification,
        badgeLabel,
        statusDetail,
        leadingTeam
    };
};