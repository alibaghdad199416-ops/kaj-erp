import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  })
}

const publicErrorCodes = new Set([
  'unauthenticated',
  'permission_denied',
  'target_membership_not_found',
  'email_already_exists',
  'user_delete_blocked',
  'invalid_input',
  'target_identity_mismatch',
  'cannot_modify_current_user',
  'erp_user_id_mismatch',
  'role_mapping_mismatch',
  'server_configuration_missing',
  'company_slug_missing',
])

function publicErrorCode(error: unknown) {
  const code = error instanceof Error ? error.message : ''
  return publicErrorCodes.has(code) ? code : 'request_failed'
}

function statusFor(code: string) {
  if (code === 'unauthenticated') return 401
  if (code === 'permission_denied') return 403
  if (code === 'target_membership_not_found') return 404
  if (['email_already_exists', 'user_delete_blocked'].includes(code)) return 409
  if (['server_configuration_missing', 'company_slug_missing', 'request_failed'].includes(code)) {
    return 500
  }
  return 422
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResponse({ ok: false, error: 'method_not_allowed' }, 405)

  try {
    const url = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!url || !anonKey || !serviceKey) throw new Error('server_configuration_missing')

    const authHeader = req.headers.get('Authorization') ?? ''
    const callerClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: authData, error: authError } = await callerClient.auth.getUser()
    if (authError || !authData.user) throw new Error('unauthenticated')

    const admin = createClient(url, serviceKey)
    const { data: callerMembership, error: callerError } = await admin
      .from('company_memberships')
      .select('company_id,role_code,is_system_admin,companies!inner(slug)')
      .eq('user_id', authData.user.id)
      .eq('is_active', true)
      .limit(1)
      .maybeSingle()
    if (callerError || !callerMembership) throw new Error('permission_denied')
    if (!callerMembership.is_system_admin && !['owner', 'admin'].includes(callerMembership.role_code)) {
      throw new Error('permission_denied')
    }

    const body = await req.json()
    const action = String(body.action ?? '').trim()
    const targetUserId = String(body.target_user_id ?? '').trim()
    const localUserId = String(body.local_user_id ?? '').trim()
    if (!['update', 'delete'].includes(action) || !targetUserId || !localUserId) {
      throw new Error('invalid_input')
    }

    const { data: targetMembership, error: targetError } = await admin
      .from('company_memberships')
      .select('company_id,user_id,local_user_id,role_code,is_system_admin')
      .eq('company_id', callerMembership.company_id)
      .eq('user_id', targetUserId)
      .maybeSingle()
    if (targetError || !targetMembership) throw new Error('target_membership_not_found')
    if (String(targetMembership.local_user_id ?? '') !== localUserId) {
      throw new Error('target_identity_mismatch')
    }
    const modifiesSelf = targetUserId === authData.user.id
    if (!modifiesSelf && targetMembership.role_code === 'owner') {
      throw new Error('permission_denied')
    }
    if (!modifiesSelf && targetMembership.role_code === 'admin' && callerMembership.role_code !== 'owner') {
      throw new Error('permission_denied')
    }

    const company = Array.isArray(callerMembership.companies)
      ? callerMembership.companies[0]
      : callerMembership.companies
    const companySlug = String(company?.slug ?? '').trim()
    if (!companySlug) throw new Error('company_slug_missing')
    const now = new Date().toISOString()

    if (action === 'delete') {
      if (modifiesSelf) throw new Error('cannot_modify_current_user')

      // Preserve the ERP row state so a failed Auth deletion can be rolled back.
      // Membership/profile rows are not disabled before deleting Auth: their
      // foreign keys cascade after a successful deletion, while historical
      // actor references are retained with ON DELETE SET NULL.
      const { data: previousRecord, error: readRecordError } = await admin
        .from('erp_records')
        .select('payload,is_deleted,deleted_at')
        .eq('company_id', companySlug)
        .eq('entity_type', 'users')
        .eq('record_id', localUserId)
        .maybeSingle()
      if (readRecordError) throw readRecordError

      const { error: recordError } = await admin
        .from('erp_records')
        .update({ is_deleted: true, deleted_at: now, updated_at: now })
        .eq('company_id', companySlug)
        .eq('entity_type', 'users')
        .eq('record_id', localUserId)
      if (recordError) throw recordError

      const { error: deleteError } = await admin.auth.admin.deleteUser(targetUserId, false)
      if (deleteError) {
        console.error('Auth user deletion failed', deleteError)
        if (previousRecord) {
          const { error: rollbackError } = await admin
            .from('erp_records')
            .update({
              payload: previousRecord.payload,
              is_deleted: previousRecord.is_deleted,
              deleted_at: previousRecord.deleted_at,
              updated_at: now,
            })
            .eq('company_id', companySlug)
            .eq('entity_type', 'users')
            .eq('record_id', localUserId)
          if (rollbackError) console.error('ERP user deletion rollback failed', rollbackError)
        }
        throw new Error('user_delete_blocked')
      }

      // These normally disappear through ON DELETE CASCADE. Explicit cleanup
      // keeps the operation idempotent for databases upgraded from old schemas.
      const { error: membershipCleanupError } = await admin
        .from('company_memberships')
        .delete()
        .eq('company_id', callerMembership.company_id)
        .eq('user_id', targetUserId)
      if (membershipCleanupError) console.error('Membership cleanup failed', membershipCleanupError)

      const { error: profileCleanupError } = await admin
        .from('profiles')
        .delete()
        .eq('id', targetUserId)
      if (profileCleanupError) console.error('Profile cleanup failed', profileCleanupError)

      return jsonResponse({ ok: true, action: 'delete' }, 200)
    }

    const email = String(body.email ?? '').trim().toLowerCase()
    const fullName = String(body.full_name ?? '').trim()
    const roleCode = String(body.role_code ?? '').trim()
    const isActive = body.is_active === true
    const erpUser = body.erp_user && typeof body.erp_user === 'object'
      ? { ...body.erp_user }
      : null
    if (!email.includes('@') || !fullName || !['owner', 'admin', 'user'].includes(roleCode) || !erpUser) {
      throw new Error('invalid_input')
    }
    if (modifiesSelf) {
      if (!isActive || roleCode !== targetMembership.role_code) {
        throw new Error('cannot_modify_current_user')
      }
    } else {
      if (roleCode === 'owner') throw new Error('permission_denied')
      if (roleCode === 'admin' && callerMembership.role_code !== 'owner') {
        throw new Error('permission_denied')
      }
    }
    if (String(erpUser.id ?? '') !== localUserId) throw new Error('erp_user_id_mismatch')
    const localRoleId = String(erpUser.roleId ?? '')
    if ((roleCode === 'admin' || roleCode === 'owner') !== (localRoleId === 'role-admin')) {
      throw new Error('role_mapping_mismatch')
    }

    const { error: authUpdateError } = await admin.auth.admin.updateUserById(targetUserId, {
      email,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    })
    if (authUpdateError) {
      if (String(authUpdateError.message ?? '').toLowerCase().includes('already')) {
        throw new Error('email_already_exists')
      }
      throw authUpdateError
    }

    const { error: profileError } = await admin.from('profiles').upsert({
      id: targetUserId,
      full_name: fullName,
      is_active: isActive,
      updated_at: now,
    }, { onConflict: 'id' })
    if (profileError) throw profileError

    const { error: membershipError } = await admin.from('company_memberships').update({
      user_email: email,
      role_code: roleCode,
      is_system_admin: roleCode === 'admin' || roleCode === 'owner',
      is_active: isActive,
      updated_at: now,
    })
      .eq('company_id', callerMembership.company_id)
      .eq('user_id', targetUserId)
    if (membershipError) throw membershipError

    const payload = {
      ...erpUser,
      id: localUserId,
      email,
      fullName,
      cloudAuthUid: targetUserId,
      authProvider: 'supabase',
      cloudEmailVerified: 1,
      passwordHash: '',
      isActive: isActive ? 1 : 0,
      updatedAt: now,
    }
    const { error: recordError } = await admin.from('erp_records').upsert({
      company_id: companySlug,
      entity_type: 'users',
      record_id: localUserId,
      payload,
      is_deleted: false,
      updated_at: now,
      deleted_at: null,
    }, { onConflict: 'company_id,entity_type,record_id' })
    if (recordError) throw recordError

    return jsonResponse({ ok: true, action: 'update' }, 200)
  } catch (error) {
    const code = publicErrorCode(error)
    console.error('admin-manage-user failed', error)
    return jsonResponse({ ok: false, error: code }, statusFor(code))
  }
})
