import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface UserData {
  phone: string;
  pwd: string;
  cookies: string;
  uid: number
}

export interface UserDataAndId {
  id: number
  phone: string;
  pwd: string;
  cookies: string;
  uid: number
}

/**
 * 可更新的用户数据接口
 */
interface UpdateUserData {
  phone?: string;
  pwd?: string;
  cookies?: string;
}

interface ExportUserEntry {
  phone: string;
  pwd: string;
  cookies: string;
  uid: number;
}

interface ExportData {
  version: number;
  exportedAt: string;
  HostUser: ExportUserEntry[];
  OtherUser: ExportUserEntry[];
}

interface ImportResult {
  success: boolean;
  message: string;
}

class DatabaseManager {
  private static instance: DatabaseManager | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;

  private constructor() {
  }

  public static getInstance(): DatabaseManager {
    if (DatabaseManager.instance === null) {
      DatabaseManager.instance = new DatabaseManager();
    }
    return DatabaseManager.instance;
  }

  public isInitialized(): boolean {
    return this.rdbStore !== null;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.rdbStore !== null) {
      return;
    }
    const STORE_CONFIG: relationalStore.StoreConfig = {
      name: 'data.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
      await this.createTables();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Failed to get RdbStore. Code: ${error.code}, Message: ${error.message}`);
    }
  }

  /**
   * 检查HostUser表是否为空
   *
   * @returns {Promise<boolean>} 如果表为空则返回true，否则返回false
   * @throws {Error} 如果数据库未初始化
   * @throws {BusinessError} 如果查询过程中发生错误
   */
  public async isHostUserTableEmpty(): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }

    try {
      // 使用高效查询：只需检查是否存在至少一行数据
      const sql = 'SELECT 1 FROM HostUser LIMIT 1';
      const resultSet = await this.rdbStore.querySql(sql);

      try {
        // rowCount为0表示没有数据
        return resultSet.rowCount === 0;
      } finally {
        // 确保无论查询结果如何都关闭结果集
        resultSet.close();
      }
    } catch (error) {
      const err = new Error(`Database init failed: ${error.message}`);
      hilog.error(0x0000, 'DB_INIT', err.message);
      throw err;
    }
  }

  /**
   * 插入用户数据（统一处理主用户和其他用户）
   * @param userData 用户数据对象
   * @param isHost 是否插入为主用户，默认false
   * @returns 插入结果状态码：1-成功，-1-手机号已存在，-2-主用户已存在，0-失败
   */
  public async insertUser(userData: UserData, isHost: boolean = false): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }

    // 输入参数验证
    if (!userData.phone || !userData.pwd || !userData.cookies || !userData.uid) {
      throw new Error('手机号、密码、cookies和uid不能为空');
    }

    if (userData.phone.trim().length === 0) {
      throw new Error('手机号不能为空字符串');
    }

    try {
      this.rdbStore.beginTransaction();

      try {
        // 检查手机号是否已存在
        const phoneExists = await this.checkPhoneExists(userData.phone);
        if (phoneExists) {
          this.rdbStore.rollBack();
          return -1; // 手机号已存在
        }

        // 如果是主用户，检查是否已有主用户
        if (isHost) {
          const isHostUserEmpty = await this.isHostUserTableEmpty();
          if (!isHostUserEmpty) {
            this.rdbStore.rollBack();
            return -2; // 主用户已存在
          }
        }

        // 根据用户类型选择表名
        const tableName = isHost ? 'HostUser' : 'OtherUser';

        // 记录插入前的记录数
        const countBefore = await this.getTableCount(tableName);

        // 执行插入操作
        const insertSql = `INSERT INTO ${tableName} (phone, pwd, cookies, uid) VALUES (?, ?, ?, ?)`;
        await this.rdbStore.executeSql(insertSql, [
          userData.phone,
          userData.pwd,
          userData.cookies,
          userData.uid
        ]);

        // 提交事务
        this.rdbStore.commit();
        // 验证插入结果：检查记录数是否增加
        const countAfter = await this.getTableCount(tableName);
        if (countAfter !== countBefore + 1) {
          throw new Error('插入操作未成功，记录数未增加');
        }


        hilog.info(0x0000, 'DB',
          `Successfully inserted ${isHost ? 'host' : 'other'} user: ${userData.phone.substring(0, 3)}***`);
        return 1; // 插入成功

      } catch (error) {
        // 回滚事务
        this.rdbStore.rollBack();
        throw Error(error);
      }
    } catch (err) {
      // 外层错误处理
      hilog.error(0x0000, 'DB', `Failed to insert ${isHost ? 'host' : 'other'} user: ${err.message}`);
      return 0; // 插入失败
    }
  }

  /**
   * 获取表中所有用户数据
   * @param isHost 是否查询主用户表，默认false
   * @returns 包含所有用户数据的数组
   */
  public async getAllUsers(isHost: boolean = false): Promise<UserDataAndId[]> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }

    const tableName = isHost ? 'HostUser' : 'OtherUser';
    const sql = `SELECT * FROM ${tableName}`;

    try {
      const resultSet = await this.rdbStore.querySql(sql);
      const users: UserDataAndId[] = [];

      while (resultSet.goToNextRow()) {
        users.push({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          phone: resultSet.getString(resultSet.getColumnIndex('phone')),
          pwd: resultSet.getString(resultSet.getColumnIndex('pwd')),
          cookies: resultSet.getString(resultSet.getColumnIndex('cookies')),
          uid: resultSet.getLong(resultSet.getColumnIndex('uid'))
        });
      }

      resultSet.close();
      return users;
    } catch (error) {
      const err = new Error(`Failed to fetch users from ${tableName}: ${error.message}`);
      hilog.error(0x0000, 'DB', err.message);
      throw err;
    }
  }

  /**
   * 更新单个用户数据
   * @param id 用户ID
   * @param userData 要更新的用户数据
   * @param isHost 是否更新主用户表，默认false
   * @returns 更新结果状态码：1-成功，-1-用户不存在，-2-手机号已存在，0-失败
   */
  public async updateUser(
    id: number,
    userData: UpdateUserData,
    isHost: boolean = false
  ): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }

    // 参数验证
    if (!Number.isInteger(id) || id <= 0) {
      throw new Error('无效的用户ID');
    }

    // 检查是否有要更新的字段
    const hasUpdateField = userData.phone !== undefined ||
      userData.pwd !== undefined ||
      userData.cookies !== undefined;

    if (!hasUpdateField) {
      throw new Error('至少需要提供一个要更新的字段');
    }

    try {
      this.rdbStore.beginTransaction();

      try {
        const tableName = isHost ? 'HostUser' : 'OtherUser';

        // 检查用户是否存在
        const userExists = await this.userExists(isHost, id);
        if (!userExists) {
          this.rdbStore.rollBack();
          return -1; // 用户不存在
        }

        // 如果要更新手机号，检查唯一性
        if (userData.phone !== undefined) {
          const phoneExists = await this.checkPhoneExists(userData.phone);
          if (phoneExists) {
            this.rdbStore.rollBack();
            return -2; // 手机号已存在
          }
        }

        // 构建更新语句
        const updateParts: string[] = [];
        const params: (string | number)[] = [];

        if (userData.phone !== undefined) {
          updateParts.push('phone = ?');
          params.push(userData.phone);
        }
        if (userData.pwd !== undefined) {
          updateParts.push('pwd = ?');
          params.push(userData.pwd);
        }
        if (userData.cookies !== undefined) {
          updateParts.push('cookies = ?');
          params.push(userData.cookies);
        }

        params.push(id);
        const updateSql = `UPDATE ${tableName} SET ${updateParts.join(', ')} WHERE id = ?`;

        // 执行更新
        await this.rdbStore.executeSql(updateSql, params);
        this.rdbStore.commit();

        return 1; // 更新成功

      } catch (error) {
        this.rdbStore.rollBack();
        throw new Error(error);
      }
    } catch (err) {
      hilog.error(0x0000, 'DB', `Failed to update user: ${err.message}`);
      return 0; // 更新失败
    }
  }

  /**
   * 根据位置获取第几条用户数据（从1开始计数）- 使用RdbPredicates
   * @param position 位置序号，从1开始
   * @param isHost 是否查询主用户表，默认false
   * @param orderBy 排序字段，默认按id排序
   * @param ascending 是否升序排列，默认true
   * @returns 用户数据或null（如果位置超出范围）
   */
  public async getUserByPosition(
    position: number,
    isHost: boolean = false,
    orderBy: string = 'id',
    ascending: boolean = true
  ): Promise<UserDataAndId | null> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }

    // 参数验证
    if (!Number.isInteger(position) || position <= 0) {
      throw new Error('位置序号必须是大于0的整数');
    }

    try {
      const tableName = isHost ? 'HostUser' : 'OtherUser';

      // 使用RdbPredicates进行查询
      let predicates = new relationalStore.RdbPredicates(tableName);

      // 设置排序
      if (ascending) {
        predicates.orderByAsc(orderBy);
      } else {
        predicates.orderByDesc(orderBy);
      }

      // 设置偏移和限制：获取第position条记录
      // offsetAs的参数是从0开始的，所以第n条记录的offset是n-1
      predicates.limitAs(1).offsetAs(position - 1);

      const resultSet = await this.rdbStore.query(predicates);

      if (resultSet.rowCount > 0) {
        resultSet.goToFirstRow();

        const userData: UserDataAndId = {
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          uid: resultSet.getLong(resultSet.getColumnIndex('uid')),
          phone: resultSet.getString(resultSet.getColumnIndex('phone')),
          pwd: resultSet.getString(resultSet.getColumnIndex('pwd')),
          cookies: resultSet.getString(resultSet.getColumnIndex('cookies'))
        };

        resultSet.close();
        return userData;
      }

      resultSet.close();
      return null; // 位置超出范围

    } catch (error) {
      hilog.error(0x0000, 'DB', `Failed to get user by position ${position}: ${error.message}`);
      throw Error(error);
    }
  }

  /**
   * 获取指定表的记录数量
   *
   * @param tableName 要查询的表名（必须是允许的表）
   * @returns {Promise<number>} 表中的记录数量
   * @throws {Error} 如果数据库未初始化或表名无效
   */
  public async getTableCount(tableName: 'HostUser' | 'OtherUser'): Promise<number> {
    // 验证表名合法性，防止SQL注入
    const allowedTables = ['HostUser', 'OtherUser'];
    if (!allowedTables.includes(tableName)) {
      throw new Error(`无效的表名: ${tableName}. 允许的表: ${allowedTables.join(', ')}`);
    }

    if (!this.rdbStore) {
      throw new Error('数据库未初始化。请先调用init()方法。');
    }

    try {
      // 使用COUNT(*)获取表记录数
      const sql = `SELECT COUNT(*) AS count FROM ${tableName}`;
      const resultSet = await this.rdbStore.querySql(sql);

      try {
        if (resultSet.rowCount > 0) {
          resultSet.goToFirstRow();
          const columnIndex = resultSet.getColumnIndex('count');
          return resultSet.getLong(columnIndex);
        }
        return 0;
      } finally {
        // 确保结果集被正确关闭
        resultSet.close();
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`获取表 ${tableName} 记录数失败. 错误码: ${error.code}, 消息: ${error.message}`);
      throw new Error(`无法获取表记录数: ${error.message}`);
    }
  }

  getRdbStore(): relationalStore.RdbStore {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }
    return this.rdbStore;
  }

  /**
   * 删除指定用户
   * @param id 用户ID
   * @param isHost 是否删除主用户表，默认false
   * @returns 删除结果状态码：1-成功，-1-用户不存在，0-失败
   */
  public async deleteUser(id: number, isHost: boolean = false): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }

    // 参数验证
    if (!Number.isInteger(id) || id <= 0) {
      throw new Error('无效的用户ID');
    }

    try {
      this.rdbStore.beginTransaction();

      try {
        const tableName = isHost ? 'HostUser' : 'OtherUser';

        // 检查用户是否存在
        const userExists = await this.userExists(isHost, id);
        if (!userExists) {
          this.rdbStore.rollBack();
          return -1; // 用户不存在
        }

        // 使用RdbPredicates进行删除
        let predicates = new relationalStore.RdbPredicates(tableName);
        predicates.equalTo('id', id);

        // 执行删除操作
        const deletedRows = await this.rdbStore.delete(predicates);

        if (deletedRows > 0) {
          this.rdbStore.commit();
          hilog.info(0x0000, 'DB', `Successfully deleted ${isHost ? 'host' : 'other'} user ID: ${id}`);
          return 1; // 删除成功
        } else {
          this.rdbStore.rollBack();
          return -1; // 没有删除任何记录
        }

      } catch (error) {
        this.rdbStore.rollBack();
        throw Error(error);
      }
    } catch (err) {
      hilog.error(0x0000, 'DB', `Failed to delete ${isHost ? 'host' : 'other'} user ID ${id}: ${err.message}`);
      return 0; // 删除失败
    }
  }

  /**
   * 清空HostUser表中的所有数据
   *
   * @returns {Promise<number>} 删除的记录数量
   * @throws {Error} 如果数据库未初始化或操作失败
   */
  public async clearHostUserTable(): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('数据库未初始化。请先调用init()方法。');
    }

    try {
      // 开始事务确保操作原子性
      this.rdbStore.beginTransaction();

      try {
        // 1. 先获取当前记录数（用于返回结果）
        const countResult = await this.rdbStore.querySql('SELECT COUNT(*) AS count FROM HostUser');
        let rowCount = 0;

        try {
          if (countResult.rowCount > 0) {
            countResult.goToFirstRow();
            rowCount = countResult.getLong(countResult.getColumnIndex('count'));
          }
        } finally {
          countResult.close();
        }

        // 2. 执行删除操作
        await this.rdbStore.executeSql('DELETE FROM HostUser');

        // 3. 重置自增ID（SQLite中需要额外操作）
        await this.rdbStore.executeSql('DELETE FROM sqlite_sequence WHERE name = "HostUser"');

        // 4. 提交事务
        this.rdbStore.commit();

        console.log(`成功清空HostUser表，删除${rowCount}条记录`);
        return rowCount;
      } catch (error) {
        // 5. 发生错误时回滚事务
        this.rdbStore.rollBack();
        throw this.normalizeError(error, '清空HostUser表失败');
      }
    } catch (err) {
      throw this.normalizeError(err, '清空HostUser表操作异常');
    }
  }

  /**
   * 导出数据库为JSON字符串
   * @returns JSON格式的数据库内容
   */
  public async exportToJSON(): Promise<string> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }

    const hostUsers = await this.getAllUsers(true);
    const otherUsers = await this.getAllUsers(false);

    const exportData: ExportData = {
      version: 1,
      exportedAt: new Date().toISOString(),
      HostUser: hostUsers.map((u: UserDataAndId): ExportUserEntry => ({
        phone: u.phone,
        pwd: u.pwd,
        cookies: u.cookies,
        uid: u.uid
      })),
      OtherUser: otherUsers.map((u: UserDataAndId): ExportUserEntry => ({
        phone: u.phone,
        pwd: u.pwd,
        cookies: u.cookies,
        uid: u.uid
      }))
    };

    return JSON.stringify(exportData, null, 2);
  }

  /**
   * 从JSON字符串导入数据库
   * @param json JSON格式的数据库内容
   * @returns 导入结果
   */
  public async importFromJSON(json: string): Promise<ImportResult> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }

    let data: ExportData;

    try {
      data = JSON.parse(json) as ExportData;
    } catch {
      const result: ImportResult = { success: false, message: '文件格式错误：无法解析JSON' };
      return result;
    }

    if (typeof data.version !== 'number') {
      const result: ImportResult = { success: false, message: '文件格式错误：缺少版本号' };
      return result;
    }
    if (!Array.isArray(data.HostUser) || !Array.isArray(data.OtherUser)) {
      const result: ImportResult = { success: false, message: '文件格式错误：缺少用户数据' };
      return result;
    }

    const validateUserEntry = (entry: ExportUserEntry, tableName: string): ImportResult | null => {
      if (typeof entry.phone !== 'string' || entry.phone.trim().length === 0) {
        const result: ImportResult = { success: false, message: `${tableName} 中存在缺少手机号的记录` };
        return result;
      }
      if (typeof entry.pwd !== 'string' || entry.pwd.trim().length === 0) {
        const result: ImportResult = { success: false, message: `${tableName} 中存在缺少密码的记录` };
        return result;
      }
      if (typeof entry.cookies !== 'string' || entry.cookies.trim().length === 0) {
        const result: ImportResult = { success: false, message: `${tableName} 中存在缺少cookies的记录` };
        return result;
      }
      if (typeof entry.uid !== 'number' || entry.uid <= 0 || !Number.isInteger(entry.uid)) {
        const result: ImportResult = { success: false, message: `${tableName} 中存在无效uid的记录` };
        return result;
      }
      return null;
    };

    for (const entry of data.HostUser) {
      const err = validateUserEntry(entry, 'HostUser');
      if (err) {
        return err;
      }
    }
    for (const entry of data.OtherUser) {
      const err = validateUserEntry(entry, 'OtherUser');
      if (err) {
        return err;
      }
    }

    try {
      this.rdbStore.beginTransaction();

      await this.rdbStore.executeSql('DELETE FROM OtherUser');
      await this.rdbStore.executeSql('DELETE FROM HostUser');
      await this.rdbStore.executeSql('DELETE FROM sqlite_sequence WHERE name = "HostUser"');
      await this.rdbStore.executeSql('DELETE FROM sqlite_sequence WHERE name = "OtherUser"');

      for (const entry of data.HostUser) {
        await this.rdbStore.executeSql(
          'INSERT INTO HostUser (phone, pwd, cookies, uid) VALUES (?, ?, ?, ?)',
          [entry.phone, entry.pwd, entry.cookies, entry.uid]
        );
      }
      for (const entry of data.OtherUser) {
        await this.rdbStore.executeSql(
          'INSERT INTO OtherUser (phone, pwd, cookies, uid) VALUES (?, ?, ?, ?)',
          [entry.phone, entry.pwd, entry.cookies, entry.uid]
        );
      }

      this.rdbStore.commit();
      const result: ImportResult = { success: true, message: `导入成功：${data.HostUser.length} 个主用户，${data.OtherUser.length} 个其他用户` };
      return result;
    } catch (err) {
      this.rdbStore.rollBack();
      const result: ImportResult = { success: false, message: `导入失败：${(err as Error).message}` };
      return result;
    }
  }

  async close(): Promise<void> {
    if (this.rdbStore) {
      try {
        await this.rdbStore.close();
        this.rdbStore = null;
      } catch (err) {
        const error = err as BusinessError;
        console.error(`Failed to close database. Code: ${error.code}, Message: ${error.message}`);
      }
    }
    DatabaseManager.instance = null;
  }

  //创建表
  private async createTables(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    try {
      await this.rdbStore.executeSql(`
        CREATE TABLE IF NOT EXISTS HostUser (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          phone TEXT NOT NULL,
          pwd TEXT NOT NULL,
          cookies TEXT NOT NULL,
          uid INTEGER NOT NULL
        );
      `);

      await this.rdbStore.executeSql(`
        CREATE TABLE IF NOT EXISTS OtherUser (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          phone TEXT NOT NULL,
          pwd TEXT NOT NULL,
          cookies TEXT NOT NULL,
          uid INTEGER NOT NULL
        );
      `);
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Failed to create tables. Code: ${error.code}, Message: ${error.message}`);
    }
  }

  private normalizeError(err: Error, message: string): Error {
    return new Error(`${message} [原因]: ${err.message}`);
  }

  // 辅助方法：检查用户是否存在
  private async userExists(isHost: boolean, id: number): Promise<boolean> {
    if (!this.rdbStore) {
      return false;
    }
    const table = isHost ? 'HostUser' : 'OtherUser';
    const sql = `SELECT 1 FROM ${table} WHERE id = ? LIMIT 1`;
    const resultSet = await this.rdbStore.querySql(sql, [id]);
    try {
      return resultSet.rowCount > 0;
    } finally {
      resultSet.close();
    }
  }

  /**
   * 检查手机号是否已存在（跨两个表检查）
   *
   * @param phone 要检查的手机号
   * @returns {Promise<boolean>} 如果手机号已存在则返回true
   */
  private async checkPhoneExists(phone: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('Database not initialized. Call init() first.');
    }

    try {
      // 使用UNION检查两个表
      const sql = `
      SELECT 1 FROM HostUser WHERE phone = ?
      UNION
      SELECT 1 FROM OtherUser WHERE phone = ?
      LIMIT 1
    `;

      const resultSet = await this.rdbStore.querySql(sql, [phone, phone]);

      try {
        return resultSet.rowCount > 0;
      } finally {
        // 确保结果集被关闭
        resultSet.close();
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`Failed to check phone existence. Code: ${error.code}, Message: ${error.message}`);
      throw new Error(`插入错误,${error}`)
    }
  }
}
export {
  DatabaseManager, UserData
}