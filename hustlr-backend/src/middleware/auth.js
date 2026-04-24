const { createClient } = require("@supabase/supabase-js");
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY,
);
const ALLOW_ADMIN_HEADER_AUTH =
  process.env.ENABLE_ADMIN_HEADER_AUTH === "true" &&
  process.env.NODE_ENV !== "production";

const authMiddleware = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res
        .status(401)
        .json({ error: "Missing or invalid authorization header" });
    }

    const token = authHeader.split(" ")[1];

    // Verify the token against the auth_sessions table
    const { data: session, error } = await supabase
      .from("auth_sessions")
      .select("user_id, is_active")
      .eq("token_hash", token)
      .single();

    if (error || !session || !session.is_active) {
      return res
        .status(401)
        .json({ error: "Session expired or invalid. Please log in again." });
    }

    // Attach user to request
    req.user = { id: session.user_id };

    // Optional dev-only escape hatch for local admin testing.
    if (
      ALLOW_ADMIN_HEADER_AUTH &&
      req.headers["x-admin-secret"] &&
      process.env.ADMIN_SECRET_KEY &&
      req.headers["x-admin-secret"] === process.env.ADMIN_SECRET_KEY
    ) {
      req.user.role = "service_role";
    }

    next();
  } catch (err) {
    console.error("[Auth] Middleware error:", err.message);
    res
      .status(500)
      .json({ error: "Internal server error during authentication" });
  }
};

module.exports = { authMiddleware };
