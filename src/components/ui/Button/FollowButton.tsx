import { BsStarFill, BsStar } from "react-icons/bs"
import { Icon } from "../Icon/Icon"
import { useFavoriteTeamsContext } from "../../../context/FavoriteTeamsContext"
import type { GameTeam } from "../../../types/sports/sportsTypes";
import { Button } from "./Button";

interface Props {
    variant?: "icon" | "button";
    team: GameTeam;
}

export const FollowButton = (props: Props) => {
    const { isFavorite, addTeam, removeTeam } = useFavoriteTeamsContext();
    const { team, variant = "button" } = props;
    const isFollowed = isFavorite(team);

    const handleClick = () => {
        if (isFollowed) {
            removeTeam(team)
        }
        else {
            addTeam(team)
        }
    }

    const StarIcon = isFollowed ? BsStarFill : BsStar;

    return (
        <>
            {variant === "button" ?
                <Button className={`follow-button`} onClick={() => handleClick()}>
                    <StarIcon />
                    {isFollowed ? "Following" : "Follow"}
                </Button>
                :
                <Icon
                    onClick={() => handleClick()}
                    Icon={StarIcon}
                />
            }
        </>
    )
}