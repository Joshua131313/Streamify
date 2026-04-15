import { useState } from "react";
import { Container } from "../../layout/Container/Container";
import "./Container.css";
import { Input } from "../../ui/Input/Input";

interface Props<T> {
    title: string;
    data: T[];
    renderItem: (item: T) => React.ReactNode;
    searchFn: (item: T, search: string) => boolean;
    defaultOpened?: boolean;
}

export function SearchableContainer<T>({
    title,
    data,
    renderItem,
    searchFn,
    defaultOpened
}: Props<T>) {
    const [search, setSearch] = useState("");

    const filtered = data.filter(item =>
        searchFn(item, search.toLowerCase().trim())
    );

    return (
        <Container title={title} accordionMode defaultOpened={defaultOpened}>
            <div className="searchable-container">
                <Input
                    className="search-input"
                    placeholder="Search..."
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                />
                <div className="search-results">
                    {filtered.map((item, i) => (
                        <div key={i}>
                            {renderItem(item)}
                        </div>
                    ))}
                </div>
            </div>
        </Container>
    );
}