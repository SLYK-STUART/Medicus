import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type Body = {
  displayName?: string;
  phoneNumber?: string;
  email?: string;
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      return jsonResponse(500, { error: "Server misconfigured", code: "config" });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse(401, { error: "Must be signed in.", code: "unauthenticated" });
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return jsonResponse(401, { error: "Must be signed in.", code: "unauthenticated" });
    }
    const callerId = userData.user.id;

    const { data: callerProfile } = await admin
      .from("profiles")
      .select("role, hospital_id")
      .eq("id", callerId)
      .maybeSingle();

    if (!callerProfile || callerProfile.role !== "receptionist") {
      return jsonResponse(403, {
        error: "Only a receptionist may create a walk-in patient record.",
        code: "permission-denied",
      });
    }

    const body = (await req.json()) as Body;
    const displayName = body.displayName?.trim();
    const phoneNumber = body.phoneNumber?.trim() || null;
    const email = body.email?.trim() || null;

    if (!displayName) {
      return jsonResponse(400, { error: "displayName is required.", code: "invalid-argument" });
    }

    // Walk-ins may have no login credentials — use a placeholder email when
    // none is provided so Auth still has a unique identity.
    const authEmail = email ?? `walkin-${crypto.randomUUID()}@patients.local`;

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email: authEmail,
      ...(phoneNumber ? { phone: phoneNumber } : {}),
      email_confirm: true,
      ...(phoneNumber ? { phone_confirm: true } : {}),
      user_metadata: { display_name: displayName },
    });

    if (createError || !created.user) {
      const message = createError?.message ?? "Failed to create patient record.";
      const already = message.toLowerCase().includes("already");
      return jsonResponse(already ? 409 : 500, {
        error: message,
        code: already ? "already-exists" : "internal",
      });
    }

    const newUserId = created.user.id;

    try {
      const { error: profileError } = await admin.from("profiles").insert({
        id: newUserId,
        email: email,
        phone_number: phoneNumber,
        display_name: displayName,
        role: "patient",
        hospital_id: null,
        has_no_login_credentials: !email,
        created_by: callerId,
      });
      if (profileError) throw profileError;

      const message = phoneNumber
        ? `${displayName} was added successfully. SMS updates will be sent to ${phoneNumber}.`
        : `${displayName} was added without a phone number — no SMS updates will be sent for their visit.`;

      const { error: notifError } = await admin.from("notifications").insert({
        user_id: callerId,
        type: phoneNumber ? "walkin_created" : "walkin_no_phone",
        message,
        hospital_id: callerProfile.hospital_id,
        appointment_id: null,
        queue_entry_id: null,
        read: false,
      });
      if (notifError) throw notifError;
    } catch (err) {
      await admin.auth.admin.deleteUser(newUserId).catch(() => {});
      const message = err instanceof Error ? err.message : "Patient setup failed; record was not created.";
      return jsonResponse(500, { error: message, code: "internal" });
    }

    return jsonResponse(200, { uid: newUserId });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unexpected error";
    return jsonResponse(500, { error: message, code: "internal" });
  }
});
