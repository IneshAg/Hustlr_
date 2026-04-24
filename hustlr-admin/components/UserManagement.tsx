'use client';
import { useState, useEffect } from 'react';
import { Users, Search, Filter, MoreHorizontal, Edit, Shield, TrendingUp } from 'lucide-react';
import AdminApiService from '@/lib/api-service';
import { useAdminData } from '@/components/AdminContext';
import type { AdminUser } from '@/lib/mock-data';

export default function UserManagement() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [tierFilter, setTierFilter] = useState('ALL');
  const [selectedUser, setSelectedUser] = useState<AdminUser | null>(null);
  const [editScore, setEditScore] = useState<number>(0);

  const { useMockData, lastRefresh } = useAdminData();

  useEffect(() => {
    loadUsers();
  }, [tierFilter, useMockData, lastRefresh]);

  const loadUsers = async () => {
    setLoading(true);
    try {
      const data = await AdminApiService.getUsers({ tier: tierFilter === 'ALL' ? undefined : tierFilter });
      setUsers(data);
      setLoading(false);
    } catch (e) {
      setLoading(false);
    }
  };

  const handleTrustScoreUpdate = async (userId: string, newScore: number) => {
    const success = await AdminApiService.updateTrustScore(userId, newScore, 'Admin adjustment');
    if (success) {
      loadUsers();
      setSelectedUser(null);
    }
  };

  const getTierColor = (tier: string) => {
    switch (tier) {
      case 'PLATINUM': return 'purple';
      case 'GOLD': return 'yellow';
      case 'SILVER': return 'gray';
      case 'BRONZE': return 'orange';
      case 'AT_RISK': return 'red';
      default: return 'gray';
    }
  };

  const getKycStatusColor = (status: string) => {
    switch (status) {
      case 'verified': return 'green';
      case 'pending': return 'orange';
      case 'rejected': return 'red';
      default: return 'gray';
    }
  };

  const filteredUsers = users.filter(
    (user) =>
      user.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      user.phone.includes(searchQuery)
  );

  return (
    <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-white">User Management</h2>
        <div className="flex items-center gap-2">
          <div className="relative">
            <Search className="absolute left-2 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search users..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-8 pr-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm"
            />
          </div>
          <div className="flex items-center gap-1 bg-gray-700 rounded-lg p-1">
            {['ALL', 'PLATINUM', 'GOLD', 'SILVER', 'BRONZE', 'AT_RISK'].map((tier) => (
              <button
                key={tier}
                onClick={() => setTierFilter(tier)}
                className={`px-3 py-1 text-xs font-bold rounded ${
                  tierFilter === tier
                    ? 'bg-green-500 text-white'
                    : 'text-gray-400 hover:text-white'
                }`}
              >
                {tier}
              </button>
            ))}
          </div>
        </div>
      </div>

      {loading ? (
        <div className="text-center py-8">
          <Users className="w-8 h-8 text-green-500 animate-spin mx-auto mb-2" />
          <p className="text-gray-400">Loading users...</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="text-left text-gray-400 text-xs uppercase border-b border-gray-700">
                <th className="pb-3 font-medium">User</th>
                <th className="pb-3 font-medium">Zone</th>
                <th className="pb-3 font-medium">Trust Score</th>
                <th className="pb-3 font-medium">Tier</th>
                <th className="pb-3 font-medium">Clean Weeks</th>
                <th className="pb-3 font-medium">Cashback</th>
                <th className="pb-3 font-medium">KYC</th>
                <th className="pb-3 font-medium">Policy</th>
                <th className="pb-3 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredUsers.map((user) => (
                <tr key={user.id} className="border-b border-gray-700/50 hover:bg-gray-700/30">
                  <td className="py-3">
                    <div>
                      <p className="text-sm font-medium text-white">{user.name}</p>
                      <p className="text-xs text-gray-400">{user.phone}</p>
                    </div>
                  </td>
                  <td className="py-3 text-sm text-gray-300">{user.zone}</td>
                  <td className="py-3">
                    <div className="flex items-center gap-2">
                      <TrendingUp className="w-4 h-4 text-green-500" />
                      <span className="text-sm font-medium text-white">{user.trustScore}</span>
                    </div>
                  </td>
                  <td className="py-3">
                    <span
                      className={`px-2 py-1 text-xs font-bold rounded bg-${getTierColor(user.trustTier)}-500/10 text-${getTierColor(user.trustTier)}-500 border border-${getTierColor(user.trustTier)}-500`}
                    >
                      {user.trustTier}
                    </span>
                  </td>
                  <td className="py-3 text-sm text-gray-300">{user.cleanWeeks}</td>
                  <td className="py-3 text-sm text-gray-300">₹{user.cashbackEarned}</td>
                  <td className="py-3">
                    <span
                      className={`px-2 py-1 text-xs font-bold rounded bg-${getKycStatusColor(user.kycStatus)}-500/10 text-${getKycStatusColor(user.kycStatus)}-500 border border-${getKycStatusColor(user.kycStatus)}-500`}
                    >
                      {user.kycStatus}
                    </span>
                  </td>
                  <td className="py-3">
                    {user.activePolicy ? (
                      <div className="flex flex-col gap-1">
                        <span className={`px-2 py-0.5 text-[10px] font-black rounded bg-green-500/10 text-green-500 border border-green-500/30 text-center uppercase`}>
                          {user.policyTier}
                        </span>
                        <span className="text-[10px] text-gray-500 text-center">₹{user.weeklyPremium}/wk</span>
                      </div>
                    ) : (
                      <span className="px-2 py-1 text-xs font-medium text-gray-600 italic">None</span>
                    )}
                  </td>
                  <td className="py-3">
                    <button
                      onClick={() => {
                        setSelectedUser(user);
                        setEditScore(user.trustScore);
                      }}
                      className="p-1 text-gray-400 hover:text-white"
                    >
                      <MoreHorizontal className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {selectedUser && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-gray-800 rounded-lg p-6 max-w-lg w-full mx-4 border border-gray-700">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-bold text-white">User Details</h3>
              <button
                onClick={() => setSelectedUser(null)}
                className="p-1 text-gray-400 hover:text-white"
              >
                <MoreHorizontal className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-xs text-gray-400 uppercase">Name</p>
                  <p className="text-sm font-medium text-white">{selectedUser.name}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Phone</p>
                  <p className="text-sm font-medium text-white">{selectedUser.phone}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Zone</p>
                  <p className="text-sm font-medium text-white">{selectedUser.zone}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">City</p>
                  <p className="text-sm font-medium text-white">{selectedUser.city}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Trust Score</p>
                  <p className="text-sm font-medium text-white">{selectedUser.trustScore}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Trust Tier</p>
                  <p className="text-sm font-medium text-white">{selectedUser.trustTier}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Clean Weeks</p>
                  <p className="text-sm font-medium text-white">{selectedUser.cleanWeeks}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Claims</p>
                  <p className="text-sm font-medium text-white">{selectedUser.claimsCount}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Cashback Earned</p>
                  <p className="text-sm font-medium text-white">₹{selectedUser.cashbackEarned}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Cashback Pending</p>
                  <p className="text-sm font-medium text-white">₹{selectedUser.cashbackPending}</p>
                </div>
              </div>

              <div className="pt-4 border-t border-gray-700">
                <p className="text-xs text-gray-400 uppercase mb-2">Update Trust Score</p>
                <div className="flex gap-2">
                  <input
                    type="number"
                    value={editScore}
                    onChange={(e) => setEditScore(parseInt(e.target.value))}
                    className="flex-1 px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm"
                  />
                  <button
                    onClick={() => handleTrustScoreUpdate(selectedUser.id, editScore)}
                    className="flex items-center gap-2 px-4 py-2 bg-green-500 text-white rounded-lg hover:bg-green-600"
                  >
                    <Edit className="w-4 h-4" />
                    Update
                  </button>
                </div>
              </div>

              <div className="pt-4 border-t border-gray-700">
                <p className="text-xs text-gray-400 uppercase mb-2">Policy Information</p>
                {selectedUser.activePolicy ? (
                  <div className="space-y-2">
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-400">Status</span>
                      <span className="text-green-500">Active</span>
                    </div>
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-400">Tier</span>
                      <span className="text-white">{selectedUser.policyTier}</span>
                    </div>
                    <div className="flex justify-between text-sm">
                      <span className="text-gray-400">Weekly Premium</span>
                      <span className="text-white">₹{selectedUser.weeklyPremium}</span>
                    </div>
                  </div>
                ) : (
                  <p className="text-sm text-gray-400">No active policy</p>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
