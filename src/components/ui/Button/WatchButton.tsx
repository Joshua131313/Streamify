import { FaPlay } from "react-icons/fa"
import { Button } from "./Button"
import type { TMediaType } from "../../../types/tmdb";
import { Link, useNavigate } from "react-router-dom";
import { useLocalStorage } from "../../../hooks/utilHooks/useLocalStorage";
import { Icon } from "../Icon/Icon";
import type { Leagues, TeamAbbrevs, TStreamProvider } from "../../../types/sports/sportsTypes";
import type { nbaTeamsMap } from "../../../data/sports/nbaData";
import type { nhlTeamsMap } from "../../../data/sports/nhlData";

interface Props {
    awayTeamAbbrev: TeamAbbrevs;
    homeTeamAbbrev: TeamAbbrevs;
    channel?: string;
    variant?: "icon" | "button";
    className?: string;
    streamProvider: TStreamProvider;
    league?: Leagues;
    onContextMenu?: (e: any) => void;
    isTV?: boolean;
}
export const getWatchURL = ({
    league,
    awayTeamAbbrev,
    homeTeamAbbrev,
    streamProvider,
    channel,
    isTV = false
}: Omit<Props, "onContextMenu" | "variant">) => {
    const params = new URLSearchParams();

    params.set("provider", streamProvider);

    if (isTV) {
        // 📺 TV mode
        if (channel) params.set("channel", channel);
        params.set("tv", "1");
    } else {
        // 🎮 Game mode
        if (league) params.set("league", league);
        if (awayTeamAbbrev) params.set("away", awayTeamAbbrev);
        if (homeTeamAbbrev) params.set("home", homeTeamAbbrev);
    }

    return `?${params.toString()}`;
};

export const WatchButton = (props: Props) => {
    const { awayTeamAbbrev, homeTeamAbbrev, className, variant, channel, streamProvider, onContextMenu, isTV = false, league } = props;
    const navigate = useNavigate();
    const watchURL = getWatchURL({ channel, league, awayTeamAbbrev, homeTeamAbbrev, streamProvider, isTV })
    return (
        <Link
            onClick={() => navigate(watchURL)}
            onContextMenu={onContextMenu && onContextMenu}
            to={watchURL}
            className={`play-button watch-button ${className}`}>
            {variant === "button" ?
                <Button className="play-button">
                    <FaPlay />
                    Watch
                </Button>
                :
                <Icon
                    Icon={FaPlay}
                />
            }
        </Link>
    )
}