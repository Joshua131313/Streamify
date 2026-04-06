import { useEffect, useRef, useState } from "react";
import { FaSearch } from "react-icons/fa";
import { Input } from "../../components/ui/Input/Input";
import "./Search.css";
import { useSearchHistory } from "../../hooks/storageHooks/useSearchHistory";
import { FaX } from "react-icons/fa6";

type Props = {
    value: string;
    onChange: (value: string) => void;
    onSearch: (value: string) => void;
};

export const SearchWithHistory = ({ value, onChange, onSearch }: Props) => {

    const { filteredHistory, addSearch, setSearchTerm, deleteSearch } = useSearchHistory();

    const [open, setOpen] = useState(false);
    const [highlighted, setHighlighted] = useState<number>(-1);

    const wrapperRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        setSearchTerm(value);
    }, [value, setSearchTerm]);

    const handleSearch = (term: string) => {
        const trimmed = term.trim();
        if (trimmed) {
            addSearch(trimmed);
        }

        onChange(trimmed);
        onSearch(trimmed);

        setOpen(false);
        setHighlighted(-1);
    };

    useEffect(() => {
        const handleClickOutside = (e: MouseEvent) => {
            if (!wrapperRef.current?.contains(e.target as Node)) {
                setOpen(false);
            }
        };

        document.addEventListener("mousedown", handleClickOutside);
        return () => document.removeEventListener("mousedown", handleClickOutside);

    }, []);

    const handleKeyDown = (e: React.KeyboardEvent) => {

        if (!open && (e.key === "ArrowDown" || e.key === "ArrowUp")) {
            setOpen(true);
            return;
        }

        if (e.key === "ArrowDown") {
            e.preventDefault();
            setHighlighted(prev =>
                prev < filteredHistory.length - 1 ? prev + 1 : 0
            );
        }

        if (e.key === "ArrowUp") {
            e.preventDefault();
            setHighlighted(prev =>
                prev > 0 ? prev - 1 : filteredHistory.length - 1
            );
        }

        if (e.key === "Enter") {
            if (highlighted >= 0) {
                handleSearch(filteredHistory[highlighted].searchValue);
            } else {
                handleSearch(value);
            }
        }
    };

    return (
        <div className="search-history-wrapper" ref={wrapperRef}>

            <Input
                autoFocus
                Icon={FaSearch}
                placeholder="Type here to search"
                value={value}
                onFocus={() => setOpen(true)}
                onChange={(e) => {
                    onChange(e.target.value);
                    setOpen(true);
                    setHighlighted(-1);
                }}
                onKeyDown={handleKeyDown}
            />

            {open && filteredHistory.length > 0 && (
                <div className="search-history-dropdown">

                    {filteredHistory.map((item, index) => (
                        <div
                            key={item.id || item.searchValue}
                            className={`search-history-item ${highlighted === index ? "highlighted" : ""}`}
                            onMouseDown={(e) => {
                                e.preventDefault();
                                handleSearch(item.searchValue);
                            }}
                        >
                            <div className="search-icon">
                                <FaSearch />
                            </div>
                            <span>{item.searchValue}</span>
                            <div
                                className="delete-search"
                                onMouseDown={(e) => {
                                    e.stopPropagation();
                                }}
                                onClick={(e) => {
                                    e.stopPropagation();
                                    deleteSearch(item.id, item.searchValue);
                                }}
                            >
                                <FaX />
                            </div>
                        </div>
                    ))}

                </div>
            )}

        </div>
    );
};