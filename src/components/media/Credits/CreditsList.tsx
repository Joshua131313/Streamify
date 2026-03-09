import { CreditCard } from "./CreditCard";
import { Credits } from "./Credits";
import "./Credits.css";

interface CreditsListProps<T> {
    items: T[] | undefined;
    title: string;
    containerId: string;
    className?: string;
    getKey: (item: T) => React.Key;
    getName: (item: T) => string;
    getSubtitle: (item: T) => string | undefined;
    getProfilePath: (item: T) => string | null;
    getId: (item: T) => number;
}

export const CreditsList = <T,>({
    items,
    title,
    containerId,
    className = "credits-list",
    getKey,
    getName,
    getSubtitle,
    getProfilePath,
    getId
}: CreditsListProps<T>) => {
    return (
        <Credits title={title} className={className} containerId={containerId}>
            {items?.map((item) => (
                <CreditCard
                    key={getKey(item)}
                    name={getName(item)}
                    subtitle={getSubtitle(item)}
                    profilePath={getProfilePath(item)}
                    id={getId(item)}
                />
            ))}
        </Credits>
    );
};