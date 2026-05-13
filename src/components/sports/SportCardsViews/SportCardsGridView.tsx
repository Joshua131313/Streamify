import type { SportCardsViewsProps } from ".";
import { FilteredSportsContainer } from "../../layout/Container/FilteredSportsContainer";
import CompactGameCard from "../GameCard/CompactGameCard";
import "./SportCardsViews.css"

export const SportCardsGridView = (props: SportCardsViewsProps) => {

    const { title, type, games, gamesLoading } = props;

    return (
        <FilteredSportsContainer className="sport-cards-grid-view" type={type} title={title}>
            {games.map((gameCard) => (
                <CompactGameCard
                    game={gameCard}
                />
            ))}
        </FilteredSportsContainer>
    )
}