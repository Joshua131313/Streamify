import { useState } from "react";
import type { GameProps, GameTeam } from "../../../types/sports/sportsTypes";
import { useFavoriteTeamsContext } from "../../../context/FavoriteTeamsContext";
import { FaHeart } from "react-icons/fa";
import { Button } from "../Button/Button";
import { BsHeart, BsHeartFill, BsStar, BsStarFill } from "react-icons/bs";

interface Props {
    game: GameProps;
    teamKey: "awayTeam" | "homeTeam";
}

export const GameCardTeam = (props: Props) => {
    const { game, teamKey } = props;
    const [animate, setAnimate] = useState(false);
    const { addTeam, isFavorite, removeTeam } = useFavoriteTeamsContext()
    const team = game[teamKey];

    const showScore = () => {
        return team.score !== undefined && (game.status === "FINAL" || game.status === "LIVE" || game.status === "HALFTIME");
    }
    const isFollowed = isFavorite(team);
    
    const Heart = isFollowed ? BsHeartFill : BsHeart;

    return (
        <div className="team">
            <div>
                <img onDoubleClick={() => {
                    if (isFollowed) {
                        removeTeam(team);
                    } else {
                        addTeam(team);
                    }

                    setAnimate(false);
                    setTimeout(() => {
                        setAnimate(true);
                    }, 0);

                    setTimeout(() => {
                        setAnimate(false);
                    }, 1000);
                }} src={team.logo} alt={team.name} />
                <Heart className={`like-response ${animate ? "animated" : ""}`} />
            </div>
            <span className="team-name">{team.name}</span>
            {(showScore()) ? (
                <div className="score">{team.score}</div>
            ) : (
                <div className="score ghost-score">-</div>
            )
            }
            <Button className="secondary follow-button" onClick={() => isFavorite(team) ? removeTeam(team) : addTeam(team)}>
                {isFavorite(team) ? <BsStarFill /> : <BsStar />}
                {isFavorite(team) ? "Following" : "Follow"}
            </Button>
        </div>
    )
}