import type { SportCardsViewsProps } from ".";
import type { GameProps, Leagues } from "../../../types/sports/sportsTypes";
import { FilteredSportsContainer } from "../../layout/Container/FilteredSportsContainer";
import HorizontalGameCard from "../GameCard/HorizontalGameCard";
import "./SportCardsViews.css"

export const SportCardsListView = (props: SportCardsViewsProps) => {

    const { title, type, games, gamesLoading } = props;
    
    return (
        <FilteredSportsContainer
            className="games-list"
            title={title}
            type={type}
        >
            {games.map((gameCard) => (
                <HorizontalGameCard
                    game={gameCard}
                />
            ))}
        </FilteredSportsContainer>
    )
}