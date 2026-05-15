
import "./GameCardSkeleton.css";

export const GameCardSkeleton = (
    props: { className?: string }
) => {

    return (

        <article
            className={`${props.className || ""} game-card-skeleton`}
        >

            <div className="game-card-skeleton-top">

                <div className="game-card-skeleton-status"></div>

                <div className="game-card-skeleton-venue"></div>

                <div className="game-card-skeleton-matchup">

                    <div className="game-card-skeleton-team">

                        <div className="game-card-skeleton-logo skeleton-shimmer"></div>

                        <div className="game-card-skeleton-score skeleton-shimmer"></div>

                        <div className="game-card-skeleton-abbr skeleton-shimmer"></div>

                    </div>

                    <div className="game-card-skeleton-team">

                        <div className="game-card-skeleton-logo skeleton-shimmer"></div>

                        <div className="game-card-skeleton-score skeleton-shimmer"></div>

                        <div className="game-card-skeleton-abbr skeleton-shimmer"></div>

                    </div>

                </div>

            </div>

            <div className="game-card-skeleton-bottom">

                <div className="game-card-skeleton-time"></div>

                <div className="game-card-skeleton-network"></div>

                <div className="game-card-skeleton-button"></div>

            </div>

        </article>
    );
};