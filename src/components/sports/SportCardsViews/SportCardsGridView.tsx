import type { SportCardsViewsProps } from ".";
import { FilteredSportsContainer } from "../../layout/Container/FilteredSportsContainer";
import { MediaSkeletonCard } from "../../ui/MediaCard/SkeletonCards/MediaSkeletonCard";
import { GameCardSkeleton } from "../GameCard/GameCardSkeleton/GameCardSkeleton";
import { SportGameCardRenderer } from "../GameCard/SportGameCardRenderer";
import "./SportCardsViews.css";

export const SportCardsGridView = (
    props: SportCardsViewsProps
) => {
    const {
        title,
        type,
        games,
        gamesLoading,
    } = props;

    return (
        <FilteredSportsContainer
            type={type}
            title={title}
        >
            <div className="sport-cards-grid">
                {gamesLoading
                    ? Array.from({ length: 8 }).map((_, index) => (
                        <GameCardSkeleton
                            key={index}
                            className="game-card-skeleton"
                        />
                    ))
                    : games.map(game => (
                        <SportGameCardRenderer
                            key={`${game.league}-${game.id}`}
                            game={game}
                        />
                    ))}
            </div>
        </FilteredSportsContainer>
    );
};