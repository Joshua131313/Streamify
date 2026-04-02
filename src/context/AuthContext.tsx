import { createContext, useContext, useEffect, useState } from "react";

interface AuthContext {
    user?: {
        email?: string | null;
        name?: string | null;
        image?: string | null;
    } | null;

    loading: boolean;

    login?: (provider?: "google", credentials?: { email: string; password: string }) => void;
    signout?: () => void;
    register?: (data: {
        firstName: string;
        lastName: string;
        email: string;
        password: string;
    }) => Promise<void>;
}

const AuthContext = createContext<AuthContext | null>(null);

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
    const [user, setUser] = useState<AuthContext["user"]>(null);
    const [loading, setLoading] = useState(true);

    return (
        <AuthContext.Provider
            value={{
                user,
                loading,

            }}
        >
            {children}
        </AuthContext.Provider>
    );
};

export const useAuthProvider = () => {
    const ctx = useContext(AuthContext);
    if (!ctx) throw new Error("Auth must be used inside AuthProvider");
    return ctx;
};