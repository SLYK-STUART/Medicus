import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ALLOWED_CREATABLE_ROLES = ["hospital_admin", "receptionist", "doctor"] as const;
type CreatableRole = (typeof ALLOWED_CREATABLE_ROLES)[number];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type Body = {
  email?: string;
  password?: string;
  displayName?: string;
  role?: string;
  hospitalId?: string;
  departmentId?: string;
  avgConsultationMinutes?: number;
  roomNumber?: string;
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

    const { data: callerProfile, error: profileError } = await admin
      .from("profiles")
      .select("role, hospital_id")
      .eq("id", callerId)
      .maybeSingle();

    if (profileError || !callerProfile) {
      return jsonResponse(403, { error: "Caller profile not found.", code: "forbidden" });
    }

    const callerRole = callerProfile.role as string;
    const callerHospitalId = callerProfile.hospital_id as string | null;

    const body = (await req.json()) as Body;
    const {
      email,
      password,
      displayName,
      role,
      hospitalId,
      departmentId,
      avgConsultationMinutes,
      roomNumber,
    } = body;

    if (!email || !password || !role) {
      return jsonResponse(400, {
        error: "email, password, and role are required.",
        code: "invalid-argument",
      });
    }
    if (!(ALLOWED_CREATABLE_ROLES as readonly string[]).includes(role)) {
      return jsonResponse(400, {
        error: `role must be one of ${ALLOWED_CREATABLE_ROLES.join(", ")}.`,
        code: "invalid-argument",
      });
    }
    if (typeof password !== "string" || password.length < 6) {
      return jsonResponse(400, {
        error: "password must be at least 6 characters.",
        code: "invalid-argument",
      });
    }
    if (role === "doctor" && !departmentId) {
      return jsonResponse(400, {
        error: "departmentId is required when creating a doctor.",
        code: "invalid-argument",
      });
    }

    let targetHospitalId: string;

    if (callerRole === "super_admin") {
      if (role !== "hospital_admin") {
        return jsonResponse(403, {
          error: "super_admin may only create hospital_admin accounts here.",
          code: "permission-denied",
        });
      }
      if (!hospitalId) {
        return jsonResponse(400, {
          error: "hospitalId is required when creating a hospital_admin.",
          code: "invalid-argument",
        });
      }
      const { data: hospital, error: hospitalError } = await admin
        .from("hospitals")
        .select("id")
        .eq("id", hospitalId)
        .maybeSingle();
      if (hospitalError || !hospital) {
        return jsonResponse(404, { error: "Hospital not found.", code: "not-found" });
      }
      targetHospitalId = hospitalId;
    } else if (callerRole === "hospital_admin") {
      if (!["receptionist", "doctor"].includes(role)) {
        return jsonResponse(403, {
          error: "hospital_admin may only create receptionist or doctor accounts.",
          code: "permission-denied",
        });
      }
      if (!callerHospitalId) {
        return jsonResponse(400, {
          error: "Caller has no hospital_id on their profile.",
          code: "failed-precondition",
        });
      }
      targetHospitalId = callerHospitalId;
    } else {
      return jsonResponse(403, {
        error: "Only super_admin or hospital_admin may create staff accounts.",
        code: "permission-denied",
      });
    }

    if (role === "doctor") {
      const { data: dept, error: deptError } = await admin
        .from("departments")
        .select("id, hospital_id")
        .eq("id", departmentId!)
        .maybeSingle();
      if (deptError || !dept) {
        return jsonResponse(404, { error: "Department not found.", code: "not-found" });
      }
      // FIX (vs Firebase): reject department that belongs to another hospital.
      if (dept.hospital_id !== targetHospitalId) {
        return jsonResponse(400, {
          error: "departmentId must belong to the caller's hospital.",
          code: "invalid-argument",
        });
      }
    }

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        display_name: displayName ?? null,
      },
    });

    if (createError || !created.user) {
      const message = createError?.message ?? "Failed to create the account.";
      const code = message.toLowerCase().includes("already") ? "already-exists" : "internal";
      const status = code === "already-exists" ? 409 : 500;
      return jsonResponse(status, { error: message, code });
    }

    const newUserId = created.user.id;

    try {
      const { error: profileInsertError } = await admin.from("profiles").insert({
        id: newUserId,
        email,
        display_name: displayName ?? null,
        role: role as CreatableRole,
        hospital_id: targetHospitalId,
        has_no_login_credentials: false,
        created_by: callerId,
      });
      if (profileInsertError) throw profileInsertError;

      if (role === "doctor") {
        const { error: doctorInsertError } = await admin.from("doctors").insert({
          id: newUserId,
          display_name: displayName ?? null,
          hospital_id: targetHospitalId,
          department_id: departmentId!,
          room_number: roomNumber || null,
          avg_consultation_minutes: avgConsultationMinutes ?? 15,
        });
        if (doctorInsertError) throw doctorInsertError;
      }
    } catch (err) {
      await admin.auth.admin.deleteUser(newUserId).catch(() => {});
      const message = err instanceof Error ? err.message : "Account setup failed; the account was not created.";
      return jsonResponse(500, { error: message, code: "internal" });
    }

    return jsonResponse(200, {
      uid: newUserId,
      email,
      role,
      hospitalId: targetHospitalId,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unexpected error";
    return jsonResponse(500, { error: message, code: "internal" });
  }
});
